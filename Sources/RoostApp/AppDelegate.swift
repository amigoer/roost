import AppKit
import RoostCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = RoostModel()
    private lazy var notch = NotchWindowController(model: model)
    private lazy var settings = SettingsWindowController(model: model)
    private lazy var approvals = ApprovalServer { [model] request in
        await model.approvals.handle(request)
    } usage: { [model] report in
        await MainActor.run { model.report(report) }
    }
    private var hitSyncTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        notch.start()
        model.startRefreshing()
        model.startCheckingForUpdates()
        model.refreshHookState()
        model.approvals.permissionMode = { [weak model] sessionId in
            await model?.permissionMode(for: sessionId) ?? nil
        }
        // A card appears the instant it is held, so the sound that goes with
        // it cannot wait for the next scan.
        model.approvals.onHold = { [weak model] _ in model?.announce() }
        approvals.start()

        // No menu bar item: another icon up there is exactly the clutter this
        // app exists to avoid. Everything lives behind the island's own gear,
        // with a right-click as the fallback for when the island is collapsed
        // and there is nothing to point at.
        notch.onGear = { [weak self] in self?.settings.show() }
        notch.onSecondaryClick = { [weak self] point in
            self?.buildMenu().popUp(positioning: nil, at: point, in: nil)
        }

        // Keep the collapsed hit target in step with the island as state changes.
        hitSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.notch.syncHitRect()
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Two items. Anything that needs explaining belongs in the window, where
    /// there is room to explain it. Built per click, so it speaks whichever
    /// language is current.
    private func buildMenu() -> NSMenu {
        let strings = model.strings
        let menu = NSMenu()
        menu.addItem(withTitle: strings.settingsMenuItem, action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: strings.quit, action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
