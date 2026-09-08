import SwiftUI
import RoostCore

/// Whose session this is, drawn in the same pixel idiom as the mascot.
///
/// Shape carries the identity and colour only reinforces it: these sit beside
/// a mascot that is already spending hue on the session's state, and two
/// things competing on colour in one row is one too many.
///
/// Motion carries something the shape cannot: whether this session is doing
/// anything. A working mark walks and a stopped one only breathes, so a row
/// answers "is it moving" from the left edge as well as the right.
extension AgentKind {
    /// Identity, so it holds still while the mascot beside it changes colour.
    var colour: NSColor {
        switch self {
        case .claudeCode: Brand.hex(0xD97757)
        case .codex: Brand.hex(0x10A37F)
        }
    }
}

/// Claude Code's terminal creature, and Codex a ring around a point -- and what
/// each of them does while a session is working.
///
/// Every animated frame is a departure the mark comes straight back from. The
/// resting frame, which is what a still shot of a row catches nine times in
/// ten, is the published mark and nothing else.
enum AgentArt {
    enum Claude {
        /// The published mark, and not an approximation of it: it is drawn with
        /// axis-aligned edges on a 1.5-unit step inside a 24-unit box, so
        /// dividing every coordinate by that step lands on whole cells. This is
        /// that mark at 16x10, exactly, rather than something redrawn to look
        /// like it.
        static let mark = [
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XX.XXXXXX.XX..",
            "..XX.XXXXXX.XX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "...X.X....X.X...",
            "...X.X....X.X...",
        ]

        /// Eyes shut. The mark's eyes are the two gaps in it, so closing them
        /// is filling them: the only frame that touches the mark's own cells,
        /// and it lasts a tenth of a second.
        static let blink = [
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "...X.X....X.X...",
            "...X.X....X.X...",
        ]

        /// Weight on the inner pair of legs, then the outer. Between them a
        /// creature with four legs is walking on them.
        static let stepIn = [
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XX.XXXXXX.XX..",
            "..XX.XXXXXX.XX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "...X.X....X.X...",
            ".....X......X...",
        ]

        static let stepOut = [
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XX.XXXXXX.XX..",
            "..XX.XXXXXX.XX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "...X.X....X.X...",
            "...X......X.....",
        ]
    }

    enum Codex {
        /// A circle gets no such luck as Claude's mark does, so it stays
        /// hand-fitted at 11x11.
        static let ring = [
            "....XXX....",
            "..XX...XX..",
            ".X.......X.",
            "X.........X",
            "X.........X",
            "X....X....X",
            "X.........X",
            "X.........X",
            ".X.......X.",
            "..XX...XX..",
            "....XXX....",
        ]

        /// The point at the centre, gone. Codex's mark has no eyes to close,
        /// so this is what standing there breathing looks like.
        static let dim = [
            "....XXX....",
            "..XX...XX..",
            ".X.......X.",
            "X.........X",
            "X.........X",
            "X.........X",
            "X.........X",
            "X.........X",
            ".X.......X.",
            "..XX...XX..",
            "....XXX....",
        ]

        /// Every other cell of the ring, clockwise from the top. A working
        /// session lights one of them at a time, which is the one thing a ring
        /// can say that a creature says by walking.
        static let orbit: [(row: Int, column: Int)] = [
            (0, 5), (1, 7), (2, 9), (4, 10), (6, 10), (8, 9), (9, 7),
            (10, 5), (9, 3), (8, 1), (6, 0), (4, 0), (2, 1), (1, 3),
        ]

        /// The ring with one cell lit.
        static func spark(at index: Int) -> [String] {
            let cell = orbit[index % orbit.count]
            var grid = ring
            var row = Array(grid[cell.row])
            row[cell.column] = "O"
            grid[cell.row] = String(row)
            return grid
        }
    }

    /// What the mark stands at, which is also what it is measured by.
    static func resting(_ kind: AgentKind) -> [String] {
        switch kind {
        case .claudeCode: Claude.mark
        case .codex: Codex.ring
        }
    }

    /// What the mark does. `working` is the only state that earns real motion:
    /// a row's left edge then says the same thing its right edge does, and a
    /// list of stopped sessions holds still the way a stopped session should.
    static func clip(_ kind: AgentKind, working: Bool) -> PixelClip {
        switch (kind, working) {
        case (.claudeCode, true):
            PixelClip(loop: [
                PixelBeat(grid: Claude.stepIn, seconds: 0.22),
                PixelBeat(grid: Claude.mark, seconds: 0.22),
                PixelBeat(grid: Claude.stepOut, seconds: 0.22),
                PixelBeat(grid: Claude.mark, seconds: 0.22),
                PixelBeat(grid: Claude.stepIn, seconds: 0.22),
                PixelBeat(grid: Claude.mark, seconds: 0.22),
                PixelBeat(grid: Claude.stepOut, seconds: 0.22),
                PixelBeat(grid: Claude.mark, seconds: 0.22),
                PixelBeat(grid: Claude.blink, seconds: 0.10),
                PixelBeat(grid: Claude.mark, seconds: 0.14),
                PixelBeat(grid: Claude.blink, seconds: 0.10),
                PixelBeat(grid: Claude.mark, seconds: 0.50),
            ])
        case (.claudeCode, false):
            // Stopped, not gone. One blink a session-length apart is the whole
            // of it -- enough that a still row does not read as a screenshot.
            PixelClip(loop: [
                PixelBeat(grid: Claude.mark, seconds: 4.40),
                PixelBeat(grid: Claude.blink, seconds: 0.10),
                PixelBeat(grid: Claude.mark, seconds: 0.20),
                PixelBeat(grid: Claude.blink, seconds: 0.10),
            ])
        case (.codex, true):
            PixelClip(loop: Codex.orbit.indices.map {
                PixelBeat(grid: Codex.spark(at: $0), seconds: 0.09)
            })
        case (.codex, false):
            PixelClip(loop: [
                PixelBeat(grid: Codex.ring, seconds: 4.40),
                PixelBeat(grid: Codex.dim, seconds: 0.10),
                PixelBeat(grid: Codex.ring, seconds: 0.20),
                PixelBeat(grid: Codex.dim, seconds: 0.10),
            ])
        }
    }

    static func inks(_ kind: AgentKind) -> [PixelInk] {
        [PixelInk(token: "X", colour: kind.colour),
         // The lit cell of Codex's ring: the same hue with the light on.
         PixelInk(token: "O",
                  colour: kind.colour.blended(withFraction: 0.5, of: .white) ?? kind.colour)]
    }
}

struct AgentMarkView: View {
    var kind: AgentKind = .claudeCode
    /// Whether the session this mark belongs to is producing anything.
    var working = false
    var cell: CGFloat = 1.5

    /// One slot in cells, whatever is standing in it, so a row's title starts
    /// in the same place whichever agent it belongs to. Sized to the widest
    /// grid and the tallest, and the art is centred rather than stretched: a
    /// mark redrawn to fill a box is no longer the mark.
    static let slot = CGSize(width: 16, height: 11)

    private var art: [String] { AgentArt.resting(kind) }

    var body: some View {
        PixelSprite(key: Key(kind: kind, working: working),
                    clip: AgentArt.clip(kind, working: working),
                    inks: AgentArt.inks(kind),
                    cell: cell,
                    rows: art.count)
            .frame(width: CGFloat(art.first?.count ?? 0) * cell,
                   height: CGFloat(art.count) * cell)
            .frame(width: Self.slot.width * cell, height: Self.slot.height * cell)
    }

    private struct Key: Hashable {
        let kind: AgentKind
        let working: Bool
    }
}
