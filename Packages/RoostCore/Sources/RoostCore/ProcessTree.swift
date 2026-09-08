import Foundation

/// Who started whom, straight from the kernel.
///
/// A session's own process is a CLI with no window of its own, so the thing a
/// click should raise is always somewhere above it: the terminal that spawned
/// the shell that spawned it, or the desktop app that started it directly.
public enum ProcessTree {
    /// The chain of parents above a pid, nearest first.
    ///
    /// Stops at `launchd`, and at a depth no honest chain reaches, because a
    /// corrupt `kinfo_proc` read as a parent pointer is how this becomes an
    /// infinite loop.
    public static func ancestors(of pid: pid_t, limit: Int = 24) -> [pid_t] {
        var chain: [pid_t] = []
        var current = pid
        var seen: Set<pid_t> = [pid]

        while chain.count < limit, let parent = parent(of: current), parent > 1 {
            guard seen.insert(parent).inserted else { break }
            chain.append(parent)
            current = parent
        }
        return chain
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }
}
