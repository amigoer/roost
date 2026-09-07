import AppKit
import RoostCore

/// Opens the session a row refers to.
enum SessionActivator {
    private static let bundleID = "com.anthropic.claudefordesktop"

    static func activate(_ session: Session) {
        // The desktop app registers exactly one route that names a session:
        // "needs-input" opens whichever has waited longest for an answer, which
        // is what a blocked row means. Nothing addresses a session by id, so
        // every other row can only raise the app itself.
        if case .blocked = session.state,
           let url = URL(string: "claude://code/needs-input?source=roost") {
            NSWorkspace.shared.open(url)
            return
        }
        raiseApp()
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
