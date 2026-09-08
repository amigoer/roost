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
    public static func resume(cliSessionId: String) -> URL? {
        guard !cliSessionId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: cliSessionId)]
        return components.url
    }
}
