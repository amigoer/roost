import AppKit

/// Coarse enter/exit from an NSTrackingArea, with a global mouse monitor spun
/// up only while hovering.
///
/// Tracking areas alone are unreliable once window ordering gets involved, and
/// an always-on global monitor burns CPU all day. Running the monitor only
/// inside the hover is Notchmeister's compromise.
@MainActor
final class HoverDetector {
    private let panel: HitPanel
    private var globalMonitor: Any?

    private(set) var isHovering = false
    var onChange: ((Bool) -> Void)?
    /// Screen-coordinate cursor reports while hovering, and clicks.
    var onMove: ((NSPoint) -> Void)?
    var onClick: ((NSPoint) -> Void)?
    /// Right-click anywhere on the island. With no menu bar item, this is the
    /// app's only menu, so it must work whether or not the island is showing.
    var onSecondaryClick: ((NSPoint) -> Void)?

    init() {
        panel = HitPanel(contentRect: .zero)
        let view = TrackingView()
        panel.contentView = view
        view.onEnter = { [weak self] in self?.enter() }
        view.onExit = { [weak self] in self?.exitIfOutside() }
        view.onClick = { [weak self] in self?.onClick?(NSEvent.mouseLocation) }
        view.onSecondaryClick = { [weak self] in self?.onSecondaryClick?(NSEvent.mouseLocation) }
    }

    func setHitRect(_ rect: NSRect) {
        guard panel.frame != rect else { return }
        panel.setFrame(rect, display: false)
        panel.orderFrontRegardless()
    }

    private func enter() {
        guard !isHovering else { return }
        isHovering = true
        onChange?(true)
        startMonitor()
    }

    /// Collapses the moment the cursor is genuinely outside, with no delay.
    ///
    /// The cursor position is re-checked rather than trusting the event alone:
    /// mouseExited also fires when the panel resizes out from under a stationary
    /// cursor, and collapsing on that would make the island flicker.
    private func exitIfOutside() {
        guard isHovering else { return }
        guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
        isHovering = false
        stopMonitor()
        onMove?(.zero)
        onChange?(false)
    }

    /// Catches the exit even when mouseExited does not arrive, and usually
    /// beats it, since it samples every mouse move rather than one boundary event.
    private func startMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.exitIfOutside()
                if self.isHovering { self.onMove?(NSEvent.mouseLocation) }
            }
        }
    }

    private func stopMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }
}

/// Transparent, borderless click target. Sits above the visual panel so the
/// visual panel can stay fully click-through.
private final class HitPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        alphaValue = 0.01
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onSecondaryClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways is required: the app is an accessory and never active.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
