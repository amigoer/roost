import Foundation

/// Installs the `PreToolUse` hook that lets the island answer permission
/// prompts, by editing the user's own settings file.
///
/// Deliberately additive and reversible: other people's hooks are left exactly
/// as they were, and removing ours puts the file back.
public enum HookInstall {
    public static func settingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }

    /// Claude Code kills a hook that overruns, and a killed hook just falls
    /// through to the normal prompt, so this sits a little above our own wait.
    static let hookTimeout = Int(ApprovalSocket.timeout) + 5

    public static func entry(command: String) -> [String: Any] {
        ["matcher": "*",
         "hooks": [["type": "command", "command": command, "timeout": hookTimeout]]]
    }

    public static func isInstalled(_ settings: [String: Any], command: String) -> Bool {
        groups(settings).contains { group in
            commands(group).contains(command)
        }
    }

    public static func adding(command: String, to settings: [String: Any]) -> [String: Any] {
        guard !isInstalled(settings, command: command) else { return settings }
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        pre.append(entry(command: command))
        hooks["PreToolUse"] = pre
        settings["hooks"] = hooks
        return settings
    }

    public static func removing(command: String, from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let pre = (hooks["PreToolUse"] as? [[String: Any]] ?? [])
            .filter { !commands($0).contains(command) }
        // Leave no empty scaffolding behind.
        if pre.isEmpty { hooks.removeValue(forKey: "PreToolUse") } else { hooks["PreToolUse"] = pre }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }

    private static func groups(_ settings: [String: Any]) -> [[String: Any]] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks["PreToolUse"] as? [[String: Any]] ?? []
    }

    private static func commands(_ group: [String: Any]) -> [String] {
        (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }

    // MARK: - Disk

    public static func read(_ url: URL = settingsURL()) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    public static func write(_ settings: [String: Any], to url: URL = settingsURL()) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
