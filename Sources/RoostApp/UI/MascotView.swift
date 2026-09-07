import SwiftUI

/// The mascot slot.
///
/// Motion is deliberately tiny and discrete, the way pixel art moves: a
/// one-cell hop while a session runs, a blinking badge while one waits on you.
///
/// Driven by Core Animation rather than SwiftUI. A `repeatForever` SwiftUI
/// animation re-evaluates the view tree every frame and measured at 13-16% CPU
/// sustained, which an always-on app cannot spend. CALayer animations run on
/// the render server instead and cost the app process nothing per frame.
struct MascotView: View {
    let face: MascotFace
    /// Points per art cell. Whole or half points only: anything else lands
    /// between device pixels and the grid stops being crisp.
    var cell: CGFloat = MascotView.large
    var animated = false

    /// Session rows.
    static let small: CGFloat = 1
    /// The collapsed island, the expanded header and the menu bar.
    static let large: CGFloat = 1.5

    var body: some View {
        Art(face: face, cell: cell, animated: animated)
            .frame(width: CGFloat(PixelChick.columns) * cell,
                   height: CGFloat(PixelChick.rows + PixelChick.hopRoom) * cell)
    }

    private struct Art: NSViewRepresentable {
        let face: MascotFace
        let cell: CGFloat
        let animated: Bool

        func makeNSView(context: Context) -> MascotNSView { MascotNSView() }

        func updateNSView(_ view: MascotNSView, context: Context) {
            view.apply(face: face, cell: cell, animated: animated)
        }
    }
}

final class MascotNSView: NSView {
    /// One layer per ink, all inside `art` so the hop can move the lot at once.
    private let art = CALayer()
    private let body = CAShapeLayer()
    private let beak = CAShapeLayer()
    private let eyes = CAShapeLayer()
    private let sweat = CAShapeLayer()
    private let badge = CAShapeLayer()
    private var inks: [CAShapeLayer] { [body, beak, eyes, sweat, badge] }
    private var current: (face: MascotFace, cell: CGFloat, animated: Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        inks.forEach(art.addSublayer)
        layer?.addSublayer(art)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        art.frame = bounds
        for ink in inks {
            ink.frame = art.bounds
            ink.contentsScale = window?.backingScaleFactor ?? 2
        }
        redraw()
    }

    func apply(face: MascotFace, cell: CGFloat, animated: Bool) {
        guard current?.face != face || current?.cell != cell
                || current?.animated != animated else { return }
        current = (face, cell, animated)
        redraw()
    }

    private func redraw() {
        guard let (face, cell, animated) = current, bounds.width > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.path = PixelChick.path("B", face: face, cell: cell)
        body.fillColor = face.bodyColour.cgColor
        beak.path = PixelChick.path("K", face: face, cell: cell)
        beak.fillColor = face.beakColour.cgColor
        eyes.path = PixelChick.path("E", face: face, cell: cell)
        eyes.fillColor = Brand.eye.cgColor
        sweat.path = PixelChick.path("S", face: face, cell: cell)
        sweat.fillColor = Brand.sweat.cgColor
        badge.path = PixelChick.path("A", face: face, cell: cell)
        badge.fillColor = face.badgeColour.cgColor
        badge.opacity = 1
        art.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()

        art.removeAllAnimations()
        badge.removeAllAnimations()
        guard animated else { return }

        switch face {
        case .running:
            art.add(hop(cell: cell, from: art.position.y), forKey: "hop")
        case .waiting, .stalled:
            badge.add(blink(), forKey: "blink")
        case .done, .error, .idle:
            break
        }
    }

    /// One cell up, one cell down, no in-between frames.
    private func hop(cell: CGFloat, from y: CGFloat) -> CAKeyframeAnimation {
        let hop = CAKeyframeAnimation(keyPath: "position.y")
        hop.values = [y, y + cell]
        hop.keyTimes = [0, 0.5]
        hop.calculationMode = .discrete
        hop.duration = 0.9
        hop.repeatCount = .infinity
        return hop
    }

    /// Blocked is the state Roost exists for, so the badge is the one thing
    /// allowed to flash. Frequency is fixed: escalation rides on the island's
    /// width instead, which is what peripheral vision actually picks up.
    private func blink() -> CAKeyframeAnimation {
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1.0, 0.2]
        blink.keyTimes = [0, 0.5]
        blink.calculationMode = .discrete
        blink.duration = 1.1
        blink.repeatCount = .infinity
        return blink
    }
}
