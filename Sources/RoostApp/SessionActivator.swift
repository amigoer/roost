import AppKit
import RoostCore

/// Opens the session a row refers to.
///
/// The desktop app has three routes in. Two of them, `code/continue` and
/// `code/needs-input`, take its own `local_` id and sit behind an account gate
/// that logs "code entry deep link gated off" and does nothing else.
///
/// The third, `claude://resume`, is the one that works, and what it does turns
/// entirely on the id it is handed: it puts `local_` back on the front, and
/// focuses the record it finds under that id. Handed the app's own id for a
/// conversation it focuses the original; handed a CLI id it finds nothing and
/// imports the transcript as a second entry beside it.
///
/// Focusing a running conversation this way was measured against the registry:
/// no record added, no second process started, one log line saying the session
/// was already there.
enum SessionActivator {
    private static let bundleID = "com.anthropic.claudefordesktop"

    static func activate(_ session: Session) {
        // Read at the click rather than carried on the session: a conversation
        // started seconds ago is not in the last scan, and opening it by the
        // wrong id duplicates it.
        let recordId = DesktopSessions.recordId(forCLISessionId: session.id)

        guard let parameter = SessionLink.resumeParameter(desktopRecordId: recordId,
                                                          cliSessionId: session.id,
                                                          entrypoint: session.entrypoint),
              let url = SessionLink.resume(session: parameter) else {
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
