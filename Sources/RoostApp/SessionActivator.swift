import AppKit
import RoostCore

/// Opens the session a row refers to.
enum SessionActivator {
    private static let bundleID = "com.anthropic.claudefordesktop"

    static func activate(_ session: Session) {
        // Raising the app is a poor answer, but it is the only one that does
        // not leave a duplicate conversation behind.
        guard session.opensWithoutCopying,
              let url = SessionLink.resume(cliSessionId: session.id) else {
            raiseApp()
            return
        }
        NSWorkspace.shared.open(url)
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
