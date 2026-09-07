import Foundation

/// Human titles the Claude desktop app keeps for its sessions.
///
/// The registry's derived `name` (e.g. "mq-studio-33") collides across sessions
/// in the same project, so prefer these when a session came from the desktop app.
public enum DesktopTitles {
    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/claude-code-sessions")
    }

    /// Maps CLI session id to title. The desktop store keys by its own session
    /// id and carries `cliSessionId` as the join key to the transcripts.
    public static func byCLISessionId(in directory: URL = defaultDirectory()) -> [String: String] {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil) else { return [:] }

        var result: [String: String] = [:]
        for case let url as URL in walker where url.pathExtension == "json" {
            guard url.lastPathComponent.hasPrefix("local_"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cliId = json["cliSessionId"] as? String,
                  let title = json["title"] as? String,
                  !title.isEmpty
            else { continue }
            result[cliId] = title
        }
        return result
    }
}
