import Foundation

/// Installs the status line command that tells Roost how much of the quota
/// windows is left.
///
/// Nothing else on this machine records it. The five-hour and seven-day
/// figures reach a status line and nowhere else -- not the transcripts, not
/// the stats cache -- so reading them means standing in that path.
///
/// Which is why this wraps rather than replaces. Whatever was configured
/// before keeps running, with the same payload on its stdin and its output
/// printed through unchanged, and it is carried base64'd in the arguments of
/// the entry Roost writes. Taking Roost back out restores it exactly, from the
/// settings file alone, whether or not this app ever runs again.
public enum StatusLineInstall {
    public static let flag = "--statusline"
    public static let wrapFlag = "--wrap"

    static let key = "statusLine"

    public static func command(helper: String, wrapping existing: [String: Any]?) -> String {
        var command = "'\(helper)' \(flag)"
        if let existing, let data = try? JSONSerialization.data(withJSONObject: existing) {
            command += " \(wrapFlag) \(data.base64EncodedString())"
        }
        return command
    }

    public static func entry(command: String) -> [String: Any] {
        ["type": "command", "command": command]
    }

    public static func isInstalled(_ settings: [String: Any], command helper: String) -> Bool {
        guard let command = configured(settings) else { return false }
        return command.contains(helper) && command.contains(flag)
    }

    public static func adding(command helper: String, to settings: [String: Any]) -> [String: Any] {
        guard !isInstalled(settings, command: helper) else { return settings }
        var settings = settings
        settings[key] = entry(command: command(helper: helper,
                                               wrapping: settings[key] as? [String: Any]))
        return settings
    }

    /// Puts back whatever Roost wrapped, or leaves no `statusLine` at all when
    /// there was nothing to wrap.
    public static func removing(command helper: String, from settings: [String: Any]) -> [String: Any] {
        guard isInstalled(settings, command: helper), let command = configured(settings)
        else { return settings }
        var settings = settings
        if let wrapped = wrapped(in: command) {
            settings[key] = wrapped
        } else {
            settings.removeValue(forKey: key)
        }
        return settings
    }

    /// The entry carried in a Roost command's arguments, decoded.
    public static func wrapped(in command: String) -> [String: Any]? {
        let parts = command.split(separator: " ").map(String.init)
        guard let marker = parts.firstIndex(of: wrapFlag), parts.indices.contains(marker + 1),
              let data = Data(base64Encoded: parts[marker + 1]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    /// The command a wrapped entry asks for, ready for `sh -c`.
    public static func wrappedCommand(in argument: String) -> String? {
        guard let data = Data(base64Encoded: argument),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String, !command.isEmpty
        else { return nil }
        return command
    }

    private static func configured(_ settings: [String: Any]) -> String? {
        (settings[key] as? [String: Any])?["command"] as? String
    }
}
