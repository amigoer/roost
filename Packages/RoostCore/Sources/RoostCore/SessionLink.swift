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
    /// Whether opening this session would leave a second entry behind.
    ///
    /// Resuming is right for a session the desktop app has never seen -- that
    /// is how a terminal session gets there in the first place. It is also free
    /// for one it has already imported. It is only wrong for a session the app
    /// started itself, where the import lands beside the original instead of on
    /// it, and nothing on offer can focus that original: the two routes that
    /// take the app's own id are gated off.
    public static func resumeIsSafe(knownToDesktop: Bool, hasImportedCopy: Bool) -> Bool {
        !knownToDesktop || hasImportedCopy
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
