import AppKit
import RoostCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = RoostModel()
    private lazy var notch = NotchWindowController(model: model)
    private lazy var menu = buildMenu()
    private lazy var approvals = ApprovalServer { [model] request in
        await model.approvals.handle(request)
    }
    private var approvalItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var autoUpdateItem: NSMenuItem?
    private var hitSyncTask: Task<Void, Never>?

    /// The hook binary rides inside the app bundle, so enabling approvals is
    /// one settings entry and no install step of its own.
    private static var hookCommand: String {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/roost-hook").path
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        notch.start()
        model.startRefreshing()
        model.startCheckingForUpdates()
        model.approvals.permissionMode = { [weak model] in model?.permissionMode(for: $0) }
        approvals.start()

        // No menu bar item: another icon up there is exactly the clutter this
        // app exists to avoid, and the island is already a target. Right-click
        // it — including the bare notch, when nothing is running — for the menu.
        notch.onSecondaryClick = { [weak self] point in
            guard let self else { return }
            menu.popUp(positioning: nil, at: point, in: nil)
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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let approvals = NSMenuItem(title: "Answer permission prompts here",
                                   action: #selector(toggleApprovals), keyEquivalent: "")
        approvals.target = self
        approvals.toolTip = "Adds a PreToolUse hook to ~/.claude/settings.json"
        menu.addItem(approvals)
        approvalItem = approvals

        let update = NSMenuItem(title: "Check for updates",
                                action: #selector(handleUpdate), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        updateItem = update

        let automatic = NSMenuItem(title: "Check automatically",
                                   action: #selector(toggleAutoUpdate), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
        autoUpdateItem = automatic

        menu.addItem(.separator())
        menu.addItem(previewItem("Live detection", nil))
        menu.addItem(.separator())
        // Forced states, so the visual design can be judged before the
        // detection layer is trusted to produce each one on demand.
        menu.addItem(previewItem("Force: dormant", .init(level: .dormant, tier: .calm, blockedCount: 0, face: .idle)))
        menu.addItem(previewItem("Force: running", .init(level: .running, tier: .calm, blockedCount: 0, face: .running)))
        menu.addItem(previewItem("Force: done", .init(level: .done, tier: .calm, blockedCount: 0, face: .done)))
        menu.addItem(previewItem("Force: waiting", .init(level: .blocked, tier: .calm, blockedCount: 1, face: .waiting)))
        menu.addItem(previewItem("Force: waiting x3", .init(level: .blocked, tier: .calm, blockedCount: 3, face: .waiting)))
        menu.addItem(previewItem("Force: waiting escalated", .init(level: .blocked, tier: .elevated, blockedCount: 1, face: .waiting)))
        menu.addItem(previewItem("Force: stalled", .init(level: .blocked, tier: .calm, blockedCount: 1, face: .stalled)))
        menu.addItem(previewItem("Force: error", .init(level: .blocked, tier: .calm, blockedCount: 1, face: .error)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Roost", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    private func previewItem(_ title: String, _ override: RoostModel.PreviewOverride?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectPreview(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = override.map(Box.init)
        return item
    }

    @objc private func selectPreview(_ sender: NSMenuItem) {
        model.previewOverride = (sender.representedObject as? Box)?.value
        notch.syncHitRect()
    }

    /// Writes the hook into the user's own settings file, and takes it back
    /// out again. Additive both ways: hooks that are not ours are untouched.
    @objc private func toggleApprovals() {
        let command = Self.hookCommand
        let settings = HookInstall.read()
        let updated = HookInstall.isInstalled(settings, command: command)
            ? HookInstall.removing(command: command, from: settings)
            : HookInstall.adding(command: command, to: settings)
        try? HookInstall.write(updated)
    }

    /// One item, two jobs: it offers the download once there is one to offer,
    /// and asks again otherwise.
    @objc private func handleUpdate() {
        if let update = model.update {
            NSWorkspace.shared.open(update.page)
            return
        }
        Task { await model.checkForUpdate(force: true) }
    }

    @objc private func toggleAutoUpdate() {
        model.checksForUpdates.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        approvalItem?.state = HookInstall.isInstalled(HookInstall.read(), command: Self.hookCommand)
            ? .on : .off
        updateItem?.title = model.update.map { "Download Roost \($0.version)…" }
            ?? "Check for updates"
        autoUpdateItem?.state = model.checksForUpdates ? .on : .off
    }
}

private final class Box: NSObject {
    let value: RoostModel.PreviewOverride
    init(_ value: RoostModel.PreviewOverride) { self.value = value }
}
