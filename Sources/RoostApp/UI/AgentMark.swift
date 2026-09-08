import SwiftUI
import RoostCore

/// Whose session this is, drawn in the same pixel idiom as the mascot.
///
/// Shape carries the identity and colour only reinforces it: these sit beside
/// a mascot that is already spending hue on the session's state, and two
/// things competing on colour in one row is one too many.
extension AgentKind {
    /// Claude Code's terminal creature, and Codex a ring around a point.
    ///
    /// The Claude one is not an approximation. Its published mark is drawn with
    /// axis-aligned edges on a 1.5-unit step inside a 24-unit box, so dividing
    /// every coordinate by that step lands on whole cells: this is that mark at
    /// 16x10, exactly, rather than something redrawn to look like it. Codex has
    /// a circle in it and gets no such luck, so it stays hand-fitted at 11x11.
    var grid: [String] {
        switch self {
        case .claudeCode:
            [
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
        case .codex:
            [
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
        }
    }

    /// Identity, so it holds still while the mascot beside it changes colour.
    var colour: Color {
        switch self {
        case .claudeCode: Brand.hex(0xD97757).swiftUI
        case .codex: Brand.hex(0x10A37F).swiftUI
        }
    }
}

struct AgentMarkView: View {
    var kind: AgentKind = .claudeCode
    var cell: CGFloat = 1.5

    /// One slot in cells, whatever is standing in it, so a row's title starts
    /// in the same place whichever agent it belongs to. Sized to the widest
    /// grid and the tallest, and the art is centred rather than stretched: a
    /// mark redrawn to fill a box is no longer the mark.
    static let slot = CGSize(width: 16, height: 11)

    var body: some View {
        PixelArt(grid: kind.grid, cell: cell)
            .fill(kind.colour)
            .frame(width: CGFloat(kind.grid.first?.count ?? 0) * cell,
                   height: CGFloat(kind.grid.count) * cell)
            .frame(width: Self.slot.width * cell, height: Self.slot.height * cell)
    }
}

/// A pixel grid as a plain shape. The mascot needs a layer per ink so it can
/// animate them separately; a mark that never moves does not.
struct PixelArt: Shape {
    let grid: [String]
    let cell: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (row, cells) in grid.enumerated() {
            for (column, character) in cells.enumerated() where character != "." {
                path.addRect(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                    width: cell, height: cell))
            }
        }
        return path
    }
}
