import AppKit
import SwiftUI

/// One ink of a pixel drawing: the character it is written with in a grid, and
/// the colour those cells are filled with.
struct PixelInk {
    let token: Character
    let colour: NSColor
    /// Whether the ink rides the drawing's motion. A badge is a label *about*
    /// the creature rather than a part of it, so it holds still while the body
    /// hops: the corner keeps saying the same thing in the same place.
    var moves = true
}

/// One held frame: which grid to draw, how far from home to draw it, and how
/// long to leave it there.
///
/// Offsets are whole cells and never anything else. Art that lands between
/// device pixels stops being pixel art, so the only motion on offer is motion
/// the grid itself can express.
struct PixelBeat {
    let grid: [String]
    let seconds: Double
    /// Positive x is right, positive y is up.
    var dx = 0
    var dy = 0
}

/// What a sprite does: a cycle, and the one-shot it plays on the way in.
struct PixelClip {
    /// The cycle. Its first beat is the resting frame -- what the drawing shows
    /// with motion switched off, and what the still exports render.
    let loop: [PixelBeat]
    /// Played once when the sprite changes into this clip, so a change of state
    /// is something you watch happen rather than a colour you notice has
    /// already changed. Ends where the loop begins.
    var arrival: [PixelBeat] = []
}

/// A grid of characters as a path of square pixels.
enum PixelGrid {
    /// `rows` is the grid's own height rather than the layer's: a sprite is
    /// given room above its art for the art to move into, and the drawing has
    /// to sit at the bottom of that box rather than in the middle of it.
    static func path(_ token: Character, grid: [String], cell: CGFloat,
                     rows: Int? = nil, origin: CGPoint = .zero) -> CGPath {
        let path = CGMutablePath()
        let height = rows ?? grid.count
        for (rowIndex, row) in grid.enumerated() {
            for (columnIndex, character) in row.enumerated() where character == token {
                // Grid rows read top-down; AppKit layers are bottom-up.
                let flipped = height - 1 - rowIndex
                path.addRect(CGRect(x: origin.x + CGFloat(columnIndex) * cell,
                                    y: origin.y + CGFloat(flipped) * cell,
                                    width: cell,
                                    height: cell))
            }
        }
        return path
    }

    /// Whether an ink draws different cells at any point in a clip.
    ///
    /// An ink that never changes is given a plain path and no animation at all.
    /// Most inks of most faces hold still -- a chick that is only blinking is
    /// not moving its feet -- and the cheapest animation is the one the render
    /// server is never handed.
    static func varies(_ token: Character, across beats: [PixelBeat]) -> Bool {
        guard let first = beats.first?.grid else { return false }
        return beats.dropFirst().contains { !matches(token, $0.grid, first) }
    }

    private static func matches(_ token: Character, _ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for (rowA, rowB) in zip(a, b) where rowA != rowB {
            guard rowA.count == rowB.count else { return false }
            for (left, right) in zip(rowA, rowB) where (left == token) != (right == token) {
                return false
            }
        }
        return true
    }
}

/// A pixel drawing that moves.
///
/// Driven by Core Animation rather than SwiftUI. A `repeatForever` SwiftUI
/// animation re-evaluates the view tree every frame and measured at 13-16% CPU
/// sustained, which an always-on app cannot spend. A `CAKeyframeAnimation` in
/// `.discrete` mode holds each frame until the next one is due and is evaluated
/// on the render server: fourteen of these animating at once measured at 0.0%
/// in the app process, which is what makes it affordable to give every row its
/// own pulse rather than only the notch.
final class PixelSpriteView: NSView {
    /// Inks that ride the motion, and inks that do not.
    private let art = CALayer()
    private let mount = CALayer()
    private var inkLayers: [Character: CAShapeLayer] = [:]
    private var shown: Request?
    private var colours: [Character: NSColor] = [:]
    /// Whether the next draw is a change of state rather than a re-layout.
    private var arriving = false
    /// What the last draw was laid out for. A draw restarts every clip from
    /// its first beat, so one per layout pass would hold every sprite on the
    /// same frame for as long as the island were resizing.
    private var drawnFor: (bounds: CGRect, scale: CGFloat)?

    private struct Request {
        let key: AnyHashable
        let clip: PixelClip
        let inks: [PixelInk]
        let cell: CGFloat
        let rows: Int
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        art.actions = ["position": NSNull()]
        layer?.addSublayer(art)
        layer?.addSublayer(mount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// `rows` is the grid's height, which is not the view's when the art has
    /// been given room to move into.
    func show(key: AnyHashable, clip: PixelClip, inks: [PixelInk], cell: CGFloat, rows: Int) {
        if let shown, shown.key == key, shown.cell == cell { return }
        arriving = shown != nil && shown?.key != key
        shown = Request(key: key, clip: clip, inks: inks, cell: cell, rows: rows)
        draw()
    }

    override func layout() {
        super.layout()
        guard drawnFor?.bounds != bounds || drawnFor?.scale != scale else { return }
        draw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        draw()
    }

    /// Core Animation drops what it is running when a layer leaves the tree, so
    /// a sprite that has been away comes back holding one frame otherwise.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { draw() }
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Motion is the whole of what this view does, so a Mac asking for less of
    /// it gets the resting frame and nothing else. Read at draw time rather
    /// than watched: the setting changes about as often as a Mac is set up.
    private var motionAllowed: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func draw() {
        guard let request = shown, bounds.width > 0,
              let rest = request.clip.loop.first else { return }
        let arriving = self.arriving
        self.arriving = false
        drawnFor = (bounds, scale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        art.frame = bounds
        mount.frame = bounds

        let before = colours
        colours = [:]
        for ink in request.inks {
            let shape = layer(for: ink)
            shape.frame = bounds
            shape.contentsScale = scale
            shape.path = PixelGrid.path(ink.token, grid: rest.grid,
                                        cell: request.cell, rows: request.rows)
            shape.fillColor = ink.colour.cgColor
            shape.removeAllAnimations()
            colours[ink.token] = ink.colour
        }
        art.removeAllAnimations()
        CATransaction.commit()

        // The state's colour crossing to the next one rather than cutting to
        // it: at notch size the hue is read before the shape is, and a cut is
        // the part of a state change that is easy to miss entirely.
        if arriving {
            for ink in request.inks {
                guard let old = before[ink.token], old != ink.colour,
                      let shape = inkLayers[ink.token] else { continue }
                let tint = CABasicAnimation(keyPath: "fillColor")
                tint.fromValue = old.cgColor
                tint.duration = 0.34
                tint.timingFunction = CAMediaTimingFunction(name: .easeOut)
                shape.add(tint, forKey: "tint")
            }
        }

        guard motionAllowed else { return }

        let clock = art.convertTime(CACurrentMediaTime(), from: nil)
        var start = clock
        let arrival = arriving ? request.clip.arrival : []
        if arrival.count > 1 {
            install(arrival, of: request, at: clock, repeats: false, named: "arrival")
            start += arrival.reduce(0) { $0 + $1.seconds }
        }
        install(request.clip.loop, of: request, at: start, repeats: true, named: "loop")
    }

    private func layer(for ink: PixelInk) -> CAShapeLayer {
        if let existing = inkLayers[ink.token] { return existing }
        let created = CAShapeLayer()
        created.actions = ["path": NSNull(), "fillColor": NSNull()]
        inkLayers[ink.token] = created
        (ink.moves ? art : mount).addSublayer(created)
        return created
    }

    /// One animation per ink that actually changes, plus one for the body's
    /// own motion. Everything shares a beat list, so nothing can drift out of
    /// step with anything else.
    private func install(_ beats: [PixelBeat], of request: Request,
                         at begin: CFTimeInterval, repeats: Bool, named name: String) {
        guard beats.count > 1 else { return }
        let total = beats.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return }

        // Discrete keyframes want one more time than value: the times are the
        // boundaries the frames are held between, and the last one closes the
        // cycle.
        var times: [NSNumber] = [0]
        var elapsed = 0.0
        for beat in beats {
            elapsed += beat.seconds
            times.append(NSNumber(value: elapsed / total))
        }

        func timeline(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = times
            animation.calculationMode = .discrete
            animation.duration = total
            animation.beginTime = begin
            animation.repeatCount = repeats ? .infinity : 1
            return animation
        }

        for ink in request.inks where PixelGrid.varies(ink.token, across: beats) {
            let frames = beats.map {
                PixelGrid.path(ink.token, grid: $0.grid, cell: request.cell, rows: request.rows)
            }
            inkLayers[ink.token]?.add(timeline("path", frames), forKey: "\(name).\(ink.token)")
        }

        guard beats.contains(where: { $0.dx != 0 || $0.dy != 0 }) else { return }
        let home = CGPoint(x: bounds.midX, y: bounds.midY)
        let positions = beats.map {
            NSValue(point: NSPoint(x: home.x + CGFloat($0.dx) * request.cell,
                                   y: home.y + CGFloat($0.dy) * request.cell))
        }
        art.add(timeline("position", positions), forKey: "\(name).motion")
    }
}

/// A sprite in a SwiftUI layout.
struct PixelSprite: NSViewRepresentable {
    let key: AnyHashable
    let clip: PixelClip
    let inks: [PixelInk]
    let cell: CGFloat
    let rows: Int

    func makeNSView(context: Context) -> PixelSpriteView { PixelSpriteView() }

    func updateNSView(_ view: PixelSpriteView, context: Context) {
        view.show(key: key, clip: clip, inks: inks, cell: cell, rows: rows)
    }
}
