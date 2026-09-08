import Foundation

/// One session as the desktop app knows it.
public struct DesktopSession: Sendable, Hashable {
    public let title: String?
    /// Raw model id, e.g. `claude-opus-4-6`.
    public let model: String?
    /// `default`, `acceptEdits`, `plan`, `bypassPermissions`. Decides whether a
    /// tool would have raised a prompt at all.
    public let permissionMode: String?

    /// Whether the app already holds a copy imported from a CLI transcript: a
    /// record whose own id is `local_<cli id>`.
    ///
    /// It dedupes imports on that derived id alone, never on which CLI session
    /// a record points at, so resuming a session it started itself lands a
    /// second entry beside the original. Resuming one it has already imported
    /// costs nothing, because the derived id is what it finds.
    public let hasImportedCopy: Bool

    public init(title: String?, model: String?, permissionMode: String?, hasImportedCopy: Bool) {
        self.title = title
        self.model = model
        self.permissionMode = permissionMode
        self.hasImportedCopy = hasImportedCopy
    }

    /// Short enough for a row: "claude-sonnet-4-5-20250929" -> "Sonnet 4.5".
    public var modelLabel: String? {
        guard let model else { return nil }
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        // Training-date suffix, which nobody reads.
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first(where: { $0.contains(where: \.isLetter) }) else { return nil }
        let version = parts.filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}

/// What the desktop app records about the sessions it started.
///
/// The registry's derived `name` (e.g. "mq-studio-33") collides across sessions
/// in the same project, and nothing else knows which model a session is on or
/// whether opening it would duplicate it, so it is worth the walk.
public enum DesktopSessions {
    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/claude-code-sessions")
    }

    /// Keyed by CLI session id: the store keys by its own id and carries
    /// `cliSessionId` as the join back to the transcripts.
    ///
    /// One conversation can have two records -- the one the app started and a
    /// copy imported from the transcript -- so they are merged: the app's own
    /// record describes the session, the copy only says that opening it is free.
    public static func byCLISessionId(in directory: URL = defaultDirectory()) -> [String: DesktopSession] {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil) else { return [:] }

        var result: [String: DesktopSession] = [:]
        for case let url as URL in walker where url.pathExtension == "json" {
            guard url.lastPathComponent.hasPrefix("local_"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cliId = json["cliSessionId"] as? String,
                  let id = json["sessionId"] as? String
            else { continue }

            let isCopy = id == "local_\(cliId)"
            let known = result[cliId]
            let hasCopy = isCopy || known?.hasImportedCopy == true

            if isCopy, let known {
                result[cliId] = DesktopSession(title: known.title, model: known.model,
                                               permissionMode: known.permissionMode,
                                               hasImportedCopy: true)
                continue
            }
            let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            result[cliId] = DesktopSession(title: title,
                                           model: json["model"] as? String,
                                           permissionMode: json["permissionMode"] as? String,
                                           hasImportedCopy: hasCopy)
        }
        return result
    }
}
