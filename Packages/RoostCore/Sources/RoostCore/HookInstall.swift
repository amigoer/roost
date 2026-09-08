import Foundation

/// Installs the hooks that let the island answer for an agent, by editing that
/// agent's own settings file.
///
/// Deliberately additive and reversible: other people's hooks are left exactly
/// as they were, and removing ours puts the file back. Claude Code keeps them
/// under `hooks` in `~/.claude/settings.json` and Codex under `hooks` in
/// `~/.codex/hooks.json`, which is the same shape in a different file.
public enum HookInstall {
    public static func settingsURL() -> URL { AgentKind.claudeCode.hooksURL }

    /// An agent kills a hook that overruns, and a killed hook just falls
    /// through to the normal prompt, so this sits a little above our own wait.
    public static let hookTimeout = Int(ApprovalSocket.timeout) + 5

    /// Lifecycle hooks are told, not asked. Nothing waits on the answer, so
    /// this only has to be long enough to write to a socket.
    public static let reportTimeout = 5

    public static func entry(command: String, timeout: Int = hookTimeout) -> [String: Any] {
        ["matcher": "*",
         "hooks": [["type": "command", "command": command, "timeout": timeout]]]
    }

    public static func isInstalled(_ settings: [String: Any], command: String,
                                   event: String = "PreToolUse") -> Bool {
        groups(settings, event: event).contains { commands($0).contains(command) }
    }

    public static func adding(command: String, to settings: [String: Any],
                              event: String = "PreToolUse",
                              timeout: Int = hookTimeout) -> [String: Any] {
        guard !isInstalled(settings, command: command, event: event) else { return settings }
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var installed = hooks[event] as? [[String: Any]] ?? []
        installed.append(entry(command: command, timeout: timeout))
        hooks[event] = installed
        settings["hooks"] = hooks
        return settings
    }

    /// Takes our command out of every event it appears under.
    ///
    /// A sweep rather than a list, because the list has grown once already and
    /// an entry left behind after an uninstall is a hook nobody can see and
    /// nobody asked for.
    public static func removing(command: String, from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !commands($0).contains(command) }
            // Leave no empty scaffolding behind.
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }

        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }

    private static func groups(_ settings: [String: Any], event: String) -> [[String: Any]] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks[event] as? [[String: Any]] ?? []
    }

    private static func commands(_ group: [String: Any]) -> [String] {
        (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }

    // MARK: - Whole agents

    /// Everything one agent needs, in one write: the events that wait for an
    /// answer, plus the ones that only say where a session got to.
    public static func adding(agent: AgentKind, command: String,
                              to settings: [String: Any]) -> [String: Any] {
        var settings = settings
        for event in agent.answerEvents {
            settings = adding(command: command, to: settings, event: event)
        }
        for event in agent.lifecycleEvents {
            settings = adding(command: command, to: settings, event: event,
                              timeout: reportTimeout)
        }
        return settings
    }

    /// True as soon as *any* of the answer events is wired up, so a file
    /// written by a version that installed fewer of them still reads as on.
    /// Adding the rest is then a repair rather than a decision.
    public static func isInstalled(agent: AgentKind, command: String,
                                   in settings: [String: Any]) -> Bool {
        agent.answerEvents.contains { isInstalled(settings, command: command, event: $0) }
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
