import AppKit
import RoostCore

/// Opens the session a row refers to.
///
/// Only ever raises the app, which is unsatisfying and is still the only thing
/// on offer that does no harm.
///
/// The desktop app has three routes in. Two of them, `code/continue` and
/// `code/needs-input`, take its own `local_` id and sit behind an account gate
/// that logs "code entry deep link gated off" and does nothing else. The third,
/// `claude://resume`, is not a way to focus a session at all: it reopens a
/// finished conversation, and pointed at a running one it starts a second
/// process against the same transcript. Every session Roost lists is running.
enum SessionActivator {
    private static let bundleID = "com.anthropic.claudefordesktop"

    static func activate(_ session: Session) {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first {
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
