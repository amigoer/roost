import Foundation

/// The link that opens a session in the desktop app.
///
/// One route works from outside: `claude://resume?session=…`. The other two,
/// `code/continue` and `code/needs-input`, take the app's own id and sit behind
/// an account gate that logs "code entry deep link gated off" and does nothing.
///
/// What the resume route does with its parameter is the whole trick. It puts
/// `local_` back on the front, looks for a record under that id, and returns
/// early when it finds one -- focusing it, touching nothing. Only when it finds
/// none does it read the transcript and import a new session.
///
/// So the parameter chooses between focusing and copying:
///
/// - the desktop app's own id for a conversation, with its prefix removed,
///   resolves back to that exact record and focuses the original;
/// - a CLI session id resolves to `local_<cli id>`, which exists only if some
///   earlier resume imported it -- otherwise the import lands *beside* the
///   original as a second entry for the same conversation;
/// - for a session the app has never seen there is no record either way, and
///   importing is exactly what should happen.
public enum SessionLink {
    static let recordPrefix = "local_"

    /// Sessions the desktop app starts itself, which always get a record of
    /// their own moments after they appear in the registry.
    static let desktopEntrypoint = "claude-desktop"

    /// What to hand the resume route, or nil when nothing can be handed to it
    /// safely.
    ///
    /// The nil case is narrow: a conversation the desktop app started so
    /// recently that its record is not on disk yet. Resuming by CLI id there
    /// would copy it, and waiting a moment costs nothing.
    public static func resumeParameter(desktopRecordId: String?,
                                       cliSessionId: String,
                                       entrypoint: String?) -> String? {
        if let desktopRecordId, desktopRecordId.hasPrefix(recordPrefix) {
            return String(desktopRecordId.dropFirst(recordPrefix.count))
        }
        guard entrypoint?.hasPrefix(desktopEntrypoint) != true else { return nil }
        return cliSessionId.isEmpty ? nil : cliSessionId
    }

    public static func resume(session parameter: String) -> URL? {
        guard !parameter.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: parameter)]
        return components.url
    }
}
