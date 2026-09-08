import AppKit
import RoostCore

/// Opens the session a row refers to, wherever it actually lives.
///
/// A session is a CLI process with no window of its own, so the thing to raise
/// is whatever started it. Walking up the process tree answers that without a
/// list of terminals to keep current: the first ancestor macOS considers a
/// running application is the window the session is sitting in, whether that
/// is Terminal, iTerm2, Ghostty, Warp or an editor's built-in one.
///
/// The desktop app is the exception, because it can do better than being
/// raised. It has three routes in, and two of them -- `code/continue` and
/// `code/needs-input` -- take its own `local_` id and sit behind an account
/// gate that logs "code entry deep link gated off" and does nothing else.
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
        // A terminal has no notion of a conversation to deep-link to; raising
        // it is the whole of what can be done, and it is what was wanted.
        if let owner = owningApplication(of: session.pid), owner.bundleIdentifier != bundleID {
            owner.activate(options: [.activateAllWindows])
            return
        }

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

    /// The nearest ancestor with windows of its own.
    ///
    /// Accessory and background processes are skipped rather than accepted:
    /// the shells and helpers between a session and its terminal are exactly
    /// what would otherwise be raised, and raising one does nothing visible.
    private static func owningApplication(of pid: pid_t) -> NSRunningApplication? {
        for ancestor in ProcessTree.ancestors(of: pid) {
            guard let app = NSRunningApplication(processIdentifier: ancestor),
                  app.activationPolicy == .regular else { continue }
            return app
        }
        return nil
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
