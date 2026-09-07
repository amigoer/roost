import AppKit
import SwiftUI
import RoostCore

/// Owns one overlay panel per screen plus the single hover target, and keeps
/// them anchored to the notch.
@MainActor
final class NotchWindowController {
    /// Panels stay a fixed generous size and only the SwiftUI content animates
    /// inside them. Resizing an NSPanel per frame makes NSHostingView relayout
    /// every tick and the morph stutters.
    private static let panelHeight: CGFloat = 420
    private static let minPanelWidth: CGFloat = 620
    /// Slack around the collapsed island. Generous vertically because the
    /// cursor almost always approaches the notch from below, and that is what
    /// decides how early the island reacts.
    private static let hitPaddingX: CGFloat = 12
    private static let hitPaddingY: CGFloat = 18

    private let model: RoostModel
    private let hover = HoverDetector()
    private var panels: [String: NotchPanel] = [:]
    private var observer: NSObjectProtocol?
    private var rebuildTask: Task<Void, Never>?

    init(model: RoostModel) {
        self.model = model
    }

    func start() {
        hover.onMove = { [weak self] point in
            self?.model.hoveredIndex = self?.rowIndex(at: point)
        }
        hover.onClick = { [weak self] point in
            guard let self, let index = rowIndex(at: point),
                  index < model.visibleSessions.count else { return }
            SessionActivator.activate(model.visibleSessions[index])
        }
        hover.onChange = { [weak self] hovering in
            guard let self else { return }
            model.isExpanded = hovering
            if !hovering { model.hoveredIndex = nil }
            // Grow the hit rect immediately, not on the animation's schedule,
            // or the cursor lands outside it and the panel closes underneath.
            updateHitRect()
        }
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    /// Called after the model changes so the collapsed hit target tracks the
    /// island as it grows and shrinks with state.
    func syncHitRect() { updateHitRect() }

    /// Screen parameter changes arrive in bursts (resolution, sleep, wake,
    /// arrangement), so collapse them into a single rebuild.
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.rebuild()
        }
    }

    private func rebuild() {
        var seen = Set<String>()

        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID else { continue }
            seen.insert(uuid)

            let anchor = screen.signalAnchorRect
            let width = min(screen.frame.width, max(anchor.width * 4, Self.minPanelWidth))
            let frame = NSRect(x: screen.frame.midX - width / 2,
                               y: screen.frame.maxY - Self.panelHeight,
                               width: width,
                               height: Self.panelHeight)

            let panel = panels[uuid] ?? {
                let created = NotchPanel(contentRect: frame)
                created.contentView = NSHostingView(
                    rootView: IslandView(model: model, notchSize: anchor.size))
                panels[uuid] = created
                return created
            }()

            panel.notchSize = anchor.size
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }

        for (uuid, panel) in panels where !seen.contains(uuid) {
            panel.orderOut(nil)
            panels.removeValue(forKey: uuid)
        }

        updateHitRect()
    }

    /// Hover is offered on the notch display only; a second monitor has no
    /// cutout to grow out of.
    private var hoverScreen: NSScreen? {
        NSScreen.screens.first(where: \.hasNotch) ?? NSScreen.main
    }

    /// Maps a screen point to a list row. The island is top-anchored, so the
    /// only thing that matters is distance down from the top of the screen.
    private func rowIndex(at point: NSPoint) -> Int? {
        guard model.isExpanded, let screen = hoverScreen else { return nil }
        let notch = screen.signalAnchorRect.size
        return IslandGeometry.rowIndex(atOffsetFromTop: screen.frame.maxY - point.y,
                                       notch: notch,
                                       rowCount: model.visibleSessions.count)
    }

    private func updateHitRect() {
        guard let screen = hoverScreen else { return }
        let anchor = screen.signalAnchorRect
        let size = IslandGeometry.size(level: model.level,
                                       tier: model.tier,
                                       notch: anchor.size,
                                       expanded: model.isExpanded,
                                       sessionCount: model.sessions.count)
        let padX = model.isExpanded ? 0 : Self.hitPaddingX
        let padY = model.isExpanded ? 0 : Self.hitPaddingY
        let rect = NSRect(x: screen.frame.midX - size.width / 2 - padX,
                          y: screen.frame.maxY - size.height - padY,
                          width: size.width + padX * 2,
                          height: size.height + padY)
        hover.setHitRect(rect)
    }
}
