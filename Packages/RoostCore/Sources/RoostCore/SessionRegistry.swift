import Foundation

/// One `~/.claude/sessions/<pid>.json` entry.
public struct RegistryEntry: Sendable, Hashable {
    public let pid: pid_t
    public let sessionId: String
    public let cwd: String
    public let name: String?
    public let startedAt: Date
    public let entrypoint: String?
}

/// Enumerates live sessions from the process registry Claude Code maintains.
public enum SessionRegistry {
    /// The registry is written a fraction of a second after the process starts
    /// (measured at under 1s across every live session on this machine), so a
    /// generous window still catches PID reuse, which is off by hours or days.
    ///
    /// Note the registry's own `procStart` string is UTC while `ps` prints local
    /// time; comparing those two directly is what makes naive checks fail by a
    /// whole timezone offset. Reading the kernel's value sidesteps that entirely.
    public static let startTimeTolerance: TimeInterval = 30

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions")
    }

    /// One entry per session id, oldest first.
    ///
    /// Reopening a session that is still running leaves a second process
    /// against the same transcript, and both write a registry file. That is one
    /// conversation, however many processes are holding it.
    public static func deduplicated(_ entries: [RegistryEntry]) -> [RegistryEntry] {
        var seen = Set<String>()
        return entries
            .sorted { $0.startedAt < $1.startedAt }
            .filter { seen.insert($0.sessionId).inserted }
    }

    public static func liveEntries(in directory: URL = defaultDirectory()) -> [RegistryEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(parse)
            .filter(isAlive)
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func parse(_ url: URL) -> RegistryEntry? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int,
              let sessionId = json["sessionId"] as? String,
              let cwd = json["cwd"] as? String
        else { return nil }

        let startedAt = (json["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return RegistryEntry(pid: pid_t(pid),
                             sessionId: sessionId,
                             cwd: cwd,
                             name: json["name"] as? String,
                             startedAt: startedAt ?? .distantPast,
                             entrypoint: json["entrypoint"] as? String)
    }

    /// A registry file outlives its process, so existence proves nothing.
    static func isAlive(_ entry: RegistryEntry) -> Bool {
        // EPERM means the pid exists but belongs to someone else.
        guard kill(entry.pid, 0) == 0 || errno == EPERM else { return false }
        guard let actual = processStartTime(entry.pid) else { return false }
        return abs(actual.timeIntervalSince(entry.startedAt)) < startTimeTolerance
    }

    /// Process start time straight from the kernel, avoiding a `ps` subprocess.
    public static func processStartTime(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
