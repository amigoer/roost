import AppKit
import RoostCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = RoostModel()
    private lazy var notch = NotchWindowController(model: model)
    private var statusItem: NSStatusItem?
    private var statusFace: MascotFace?
    private var hitSyncTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        notch.start()
        model.startRefreshing()
        installStatusItem()

        // Keep the collapsed hit target and the menu bar mark in step with the
        // island as state changes.
        hitSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.notch.syncHitRect()
                self?.refreshStatusIcon()
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Roost"

        let menu = NSMenu()
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

        item.menu = menu
        statusItem = item
        refreshStatusIcon()
    }

    /// The menu bar wears the same mark as the island, so the two never
    /// disagree about what is going on.
    private func refreshStatusIcon() {
        let face = model.face
        guard face != statusFace else { return }
        statusFace = face
        statusItem?.button?.image = PixelChick.image(face, cell: MascotView.large)
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
        refreshStatusIcon()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private final class Box: NSObject {
    let value: RoostModel.PreviewOverride
    init(_ value: RoostModel.PreviewOverride) { self.value = value }
}
