import AppKit
import RoostCore

/// Opens the session a row refers to.
enum SessionActivator {
    private static let bundleID = "com.anthropic.claudefordesktop"

    static func activate(_ session: Session) {
        guard let url = deepLink(for: session) else {
            raiseApp()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// `continue` is the route that takes a session, and the only handle it
    /// accepts is the desktop app's own `local_<uuid>`; hand it a CLI session
    /// id and it drops the parameter and just raises the app, which is what
    /// used to happen here.
    ///
    /// Without a desktop id there is nothing to name, so a blocked row falls
    /// back to `needs-input`: it opens whichever session has waited longest,
    /// which is usually the one that was clicked.
    private static func deepLink(for session: Session) -> URL? {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        var query = [URLQueryItem(name: "source", value: "roost")]

        if let desktopId = session.desktopId {
            components.path = "/continue"
            query.append(URLQueryItem(name: "session", value: desktopId))
        } else if case .blocked = session.state {
            components.path = "/needs-input"
        } else {
            return nil
        }

        components.queryItems = query
        return components.url
    }

    private static func raiseApp() {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first {
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
