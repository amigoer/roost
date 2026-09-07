import AppKit

/// Click-through overlay that paints the signal. It must never take focus and
/// must never swallow clicks meant for the menu bar underneath, including the
/// system's own menu bar overflow control.
final class NotchPanel: NSPanel {
    /// Cutout size for the screen this panel is pinned to.
    var notchSize: CGSize = .zero

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        // Must exceed .mainMenu (24) to paint over the menu bar. .screenSaver
        // (1000) would also cover the screensaver and security dialogs.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
