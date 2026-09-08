import Foundation

/// The link that opens a session in the desktop app.
///
/// There are three routes and only one of them works from outside. `resume`
/// takes the CLI session id -- the same id the registry and the transcript use
/// -- imports that conversation if the desktop app has not seen it, and focuses
/// it either way. Repeats are idempotent: the second click focuses what the
/// first imported.
///
/// The other two, `code/continue` and `code/needs-input`, take the desktop
/// app's own `local_` id and sit behind an account gate that logs
/// "code entry deep link gated off" and does nothing else. Sending those is how
/// a click used to end up merely raising the app.
public enum SessionLink {
    /// Sessions the desktop app starts itself. It files its own record for
    /// these under an id of its own, which is what makes a later import land
    /// beside the original rather than on it.
    static let desktopEntrypoint = "claude-desktop"

    /// Whether opening this session would leave a second entry behind.
    ///
    /// Resuming is right for a session the desktop app has never seen -- that
    /// is how a terminal session gets there in the first place -- and free for
    /// one it has already imported, where the import is found rather than made.
    ///
    /// `knownToDesktop` comes from a scan of the store, so a conversation
    /// started seconds ago is not in it yet. The entrypoint is the guard for
    /// that window: it comes from the session's own registry file, is there the
    /// moment the session is, and says who started it. Without it, clicking a
    /// brand new desktop conversation duplicated it.
    public static func resumeIsSafe(entrypoint: String?,
                                    knownToDesktop: Bool,
                                    hasImportedCopy: Bool) -> Bool {
        if hasImportedCopy { return true }
        if knownToDesktop { return false }
        return entrypoint?.hasPrefix(desktopEntrypoint) != true
    }

    public static func resume(cliSessionId: String) -> URL? {
        guard !cliSessionId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: cliSessionId)]
        return components.url
    }
}
