import AppKit
import SwiftUI
import RoostCore

/// Owns one island per screen, each with its own hover target, and keeps them
/// anchored to their display's notch.
///
/// Per screen rather than per app: the sessions are the same everywhere, but
/// pointing at the island on one display must not open the island on another,
/// and a display without a physical notch still gets a target of its own.
@MainActor
final class NotchWindowController {
    /// Right-click on any island, in screen coordinates.
    var onSecondaryClick: ((NSPoint) -> Void)?
    /// The gear in an island's header.
    var onGear: (() -> Void)?

    /// Panels stay a fixed generous size and only the SwiftUI content animates
    /// inside them. Resizing an NSPanel per frame makes NSHostingView relayout
    /// every tick and the morph stutters.
    /// Tall enough for the largest island there is: a plan card above a full
    /// list. The panel is click-through, so spare height costs nothing, while
    /// too little of it silently clips the bottom row.
    private static let panelHeight: CGFloat = 620
    private static let minPanelWidth: CGFloat = 620
    /// Slack around the collapsed island. Generous vertically because the
    /// cursor almost always approaches the notch from below, and that is what
    /// decides how early the island reacts.
    private static let hitPaddingX: CGFloat = 12
    private static let hitPaddingY: CGFloat = 18

    private struct Island {
        let panel: NotchPanel
        let state: IslandState
        let hover: HoverDetector
    }

    private let model: RoostModel
    private var islands: [String: Island] = [:]
    private var observer: NSObjectProtocol?
    private var rebuildTask: Task<Void, Never>?

    init(model: RoostModel) {
        self.model = model
    }

    func start() {
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    /// Called after the model changes so every collapsed hit target tracks its
    /// island as it grows and shrinks with state.
    func syncHitRect() {
        for uuid in islands.keys { updateHitRect(uuid) }
    }

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
            let island = islands[uuid] ?? make(for: uuid, screen: screen)
            islands[uuid] = island

            island.panel.notchSize = anchor.size
            island.panel.setFrame(panelFrame(on: screen), display: true)
            // The cutout size is baked into the view, so a display that changed
            // resolution needs the root view rebuilt, not just the panel moved.
            (island.panel.contentView as? NSHostingView<IslandView>)?.rootView =
                IslandView(model: model, state: island.state, notchSize: anchor.size)
            island.panel.orderFrontRegardless()
        }

        for (uuid, island) in islands where !seen.contains(uuid) {
            island.panel.orderOut(nil)
            island.hover.stop()
            islands.removeValue(forKey: uuid)
        }

        syncHitRect()
    }

    private func make(for uuid: String, screen: NSScreen) -> Island {
        let state = IslandState()
        let panel = NotchPanel(contentRect: panelFrame(on: screen))
        panel.contentView = NSHostingView(
            rootView: IslandView(model: model, state: state, notchSize: screen.signalAnchorRect.size))

        let hover = HoverDetector()
        hover.onChange = { [weak self] hovering in
            guard let self, let island = islands[uuid] else { return }
            island.state.isExpanded = hovering
            // Any island open is somebody looking, which is what decides how
            // often the quota poll is worth making.
            model.isWatched = islands.values.contains { $0.state.isExpanded }
            if !hovering {
                island.state.hoveredIndex = nil
                island.state.hoveredApproval = nil
                island.state.hoveredOption = nil
                island.state.hoveredMenu = false
            }
            // Grow the hit rect immediately, not on the animation's schedule,
            // or the cursor lands outside it and the panel closes underneath.
            updateHitRect(uuid)
        }
        hover.onMove = { [weak self] point in
            guard let self, let island = islands[uuid] else { return }
            island.state.hoveredMenu = menuHit(at: point, on: uuid)
            island.state.hoveredApproval = approvalHit(at: point, on: uuid)
            island.state.hoveredOption = optionIndex(at: point, on: uuid)
            let onHeldCall = island.state.hoveredApproval != nil || island.state.hoveredOption != nil
            island.state.hoveredIndex = onHeldCall ? nil : rowIndex(at: point, on: uuid)
        }
        hover.onClick = { [weak self] point in
            guard let self else { return }
            if menuHit(at: point, on: uuid) {
                onGear?()
                return
            }
            if let held = model.approvals.current {
                if let hit = approvalHit(at: point, on: uuid) {
                    model.approvals.decide(held.id, hit == .allow ? .allow : .deny)
                    return
                }
                if let option = optionIndex(at: point, on: uuid) {
                    model.approvals.answer(held.id, option: option)
                    return
                }
            }
            guard let index = rowIndex(at: point, on: uuid),
                  index < model.visibleSessions.count else { return }
            SessionActivator.activate(model.visibleSessions[index])
        }
        hover.onSecondaryClick = { [weak self] point in
            self?.onSecondaryClick?(point)
        }
        return Island(panel: panel, state: state, hover: hover)
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let anchor = screen.signalAnchorRect
        let width = min(screen.frame.width, max(anchor.width * 4, Self.minPanelWidth))
        return NSRect(x: screen.frame.midX - width / 2,
                      y: screen.frame.maxY - Self.panelHeight,
                      width: width,
                      height: Self.panelHeight)
    }

    private func screen(_ uuid: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayUUID == uuid }
    }

    /// Maps a screen point to a list row. The island is top-anchored, so the
    /// only thing that matters is distance down from the top of that screen.
    private func rowIndex(at point: NSPoint, on uuid: String) -> Int? {
        guard let island = islands[uuid], let screen = screen(uuid),
              island.state.showsPanel(pinned: model.isPinned) else { return nil }
        return IslandGeometry.rowIndex(atOffsetFromTop: screen.frame.maxY - point.y,
                                       notch: screen.signalAnchorRect.size,
                                       rowCount: model.visibleSessions.count,
                                       heldHeight: model.heldHeight)
    }

    private func menuHit(at point: NSPoint, on uuid: String) -> Bool {
        guard let island = islands[uuid], let screen = screen(uuid),
              island.state.showsPanel(pinned: model.isPinned) else { return false }
        let notch = screen.signalAnchorRect.size
        let width = IslandGeometry.expandedSize(notch: notch,
                                                sessionCount: model.visibleSessions.count,
                                                hasFooter: model.hasFooter,
                                                heldHeight: model.heldHeight).width
        return IslandGeometry.menuHit(offsetFromTop: screen.frame.maxY - point.y,
                                      offsetFromLeft: point.x - (screen.frame.midX - width / 2),
                                      notch: notch,
                                      islandWidth: width)
    }

    /// The island is centred on its own screen, so a click has to be measured
    /// from that island's left edge before the card's buttons mean anything.
    private func approvalHit(at point: NSPoint, on uuid: String) -> IslandGeometry.ApprovalHit? {
        guard let kind = model.approvals.current?.kind, let screen = screen(uuid) else { return nil }
        let notch = screen.signalAnchorRect.size
        let width = IslandGeometry.expandedSize(notch: notch,
                                                sessionCount: model.visibleSessions.count,
                                                hasFooter: model.hasFooter,
                                                heldHeight: model.heldHeight).width
        let y = screen.frame.maxY - point.y
        let x = point.x - (screen.frame.midX - width / 2)
        switch kind {
        case .permission:
            return IslandGeometry.approvalHit(offsetFromTop: y, offsetFromLeft: x,
                                              notch: notch, islandWidth: width)
        case .plan:
            return IslandGeometry.planHit(offsetFromTop: y, offsetFromLeft: x,
                                          notch: notch, islandWidth: width)
        case .question:
            return nil
        }
    }

    /// An answer is a full-width row, so only the distance down the island
    /// matters -- the same measurement the session rows below it use.
    private func optionIndex(at point: NSPoint, on uuid: String) -> Int? {
        guard case .question(let question) = model.approvals.current?.kind,
              let screen = screen(uuid) else { return nil }
        return IslandGeometry.optionIndex(offsetFromTop: screen.frame.maxY - point.y,
                                          notch: screen.signalAnchorRect.size,
                                          optionCount: question.options.count)
    }

    private func updateHitRect(_ uuid: String) {
        guard let island = islands[uuid], let screen = screen(uuid) else { return }
        let anchor = screen.signalAnchorRect
        let expanded = island.state.showsPanel(pinned: model.isPinned)
        let size = IslandGeometry.size(level: model.level,
                                       tier: model.tier,
                                       notch: anchor.size,
                                       expanded: expanded,
                                       sessionCount: model.visibleSessions.count,
                                       hasFooter: model.hasFooter,
                                       heldHeight: model.heldHeight)
        let padX = expanded ? 0 : Self.hitPaddingX
        let padY = expanded ? 0 : Self.hitPaddingY
        island.hover.setHitRect(NSRect(x: screen.frame.midX - size.width / 2 - padX,
                                       y: screen.frame.maxY - size.height - padY,
                                       width: size.width + padX * 2,
                                       height: size.height + padY))
    }
}
