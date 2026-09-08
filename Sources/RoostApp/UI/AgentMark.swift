import SwiftUI
import RoostCore

/// Whose session this is, drawn in the same pixel idiom as the mascot.
///
/// Shape carries the identity and colour only reinforces it: these sit beside
/// a mascot that is already spending hue on the session's state, and two
/// things competing on colour in one row is one too many.
extension AgentKind {
    /// Claude Code is an eight-ray burst, Codex a ring around a point. Both on
    /// an 11x11 grid, and both sparse on purpose: at 16pt the dotted diagonals
    /// still read as rays, while anything thicker turns into a blob.
    var grid: [String] {
        switch self {
        case .claudeCode:
            [
                ".....X.....",
                ".X...X...X.",
                "..X..X..X..",
                "...X.X.X...",
                "....XXX....",
                "XXXXXXXXXXX",
                "....XXX....",
                "...X.X.X...",
                "..X..X..X..",
                ".X...X...X.",
                ".....X.....",
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

    var body: some View {
        PixelArt(grid: kind.grid, cell: cell)
            .fill(kind.colour)
            .frame(width: CGFloat(kind.grid.first?.count ?? 0) * cell,
                   height: CGFloat(kind.grid.count) * cell)
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
