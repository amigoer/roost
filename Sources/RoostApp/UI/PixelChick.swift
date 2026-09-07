import AppKit
import RoostCore

/// What the chick's face is saying.
enum MascotFace: String, CaseIterable, Sendable {
    /// Working: plain eyes, no badge, a one-pixel hop.
    case running
    /// Stopped on something only a person can answer: wide eyes, amber "?".
    case waiting
    /// A tool that will not finish: squint, sweat drop, red "!".
    case stalled
    /// Turn ended: happy eyes, green tick.
    case done
    /// Something failed: crossed eyes, red "x".
    case error
    /// Nothing to report: closed eyes, grey "z", grey body.
    case idle
}

/// The mascot art, drawn from an editable grid.
///
/// Each face is 15x12 cells: the chick fills the left 11 columns and the badge
/// sits in the top-right corner, so the body stays put from face to face and
/// only the corner changes. `B` body, `K` beak and feet, `E` eye, `A` badge,
/// `S` sweat drop, `.` transparent.
enum PixelChick {
    static let columns = 15
    static let rows = 12
    /// A spare row above the grid, so the running hop has somewhere to go.
    static let hopRoom = 1

    static func grid(_ face: MascotFace) -> [String] {
        switch face {
        case .running:
            [
                "...BBBBB.......",
                "..BBBBBBB......",
                ".BBBBBBBBB.....",
                ".BBEBBBEBB.....",
                "BBBEBKBEBBB....",
                "BBBBBKBBBBB....",
                ".BBBBBBBBB.....",
                ".BBBBBBBBB.....",
                "..BBBBBBB......",
                "...BBBBB.......",
                "....K.K........",
                "...............",
            ]
        case .waiting:
            [
                "...BBBBB...AAA.",
                "..BBBBBBB....A.",
                ".BBBBBBBBB..A..",
                ".BEEBBBEEB..A..",
                "BBEEBKBEEBB....",
                "BBBBBKBBBBB.A..",
                ".BBBBBBBBB.....",
                ".BBBBBBBBB.....",
                "..BBBBBBB......",
                "...BBBBB.......",
                "....K.K........",
                "...............",
            ]
        case .stalled:
            [
                "...BBBBB....A..",
                "..BBBBBBB...A..",
                ".BBBBBBBBBS.A..",
                ".BBBBBBBBBS.A..",
                "BBBEBKBEBBB....",
                "BBBBBKBBBBB.A..",
                ".BBBBBBBBB.....",
                ".BBBBBBBBB.....",
                "..BBBBBBB......",
                "...BBBBB.......",
                "....K.K........",
                "...............",
            ]
        case .done:
            [
                "...BBBBB.......",
                "..BBBBBBB.....A",
                ".BBBBBBBBB...A.",
                ".BBEBBBEBBA.A..",
                "BBEBEKEBEBBA...",
                "BBBBBKBBBBB....",
                ".BBBBBBBBB.....",
                ".BBBBBBBBB.....",
                "..BBBBBBB......",
                "...BBBBB.......",
                "....K.K........",
                "...............",
            ]
        case .error:
            [
                "...BBBBB...A.A.",
                "..BBBBBBB...A..",
                ".BBBBBBBBB.A.A.",
                ".BEBBBBBEB.....",
                "BBBEBKBEBBB....",
                "BBBBBKBBBBB....",
                ".BBBBBBBBB.....",
                ".BBBBBBBBB.....",
                "..BBBBBBB......",
                "...BBBBB.......",
                "....K.K........",
                "...............",
            ]
        case .idle:
            [
                "...BBBBB...AAA.",
                "..BBBBBBB...A..",
                ".BBBBBBBBB.AAA.",
                ".BBBBBBBBB.....",
                "BBEEBKBEEBB....",
                "BBBBBKBBBBB....",
                ".BBBBBBBBB.....",
                ".BBBBBBBBB.....",
                "..BBBBBBB......",
                "...BBBBB.......",
                "....K.K........",
                "...............",
            ]
        }
    }

    /// Cells of one kind, as a path of square pixels.
    static func path(_ token: Character, face: MascotFace,
                     cell: CGFloat, origin: CGPoint = .zero) -> CGPath {
        let path = CGMutablePath()
        for (rowIndex, row) in grid(face).enumerated() {
            for (columnIndex, character) in row.enumerated() where character == token {
                // Grid rows read top-down; AppKit layers are bottom-up.
                let flipped = rows - 1 - rowIndex
                path.addRect(CGRect(x: origin.x + CGFloat(columnIndex) * cell,
                                    y: origin.y + CGFloat(flipped) * cell,
                                    width: cell,
                                    height: cell))
            }
        }
        return path
    }
}

extension MascotFace {
    /// The state's colour. Worn by the body, the badge, and any text that is
    /// talking about the same session, so one hue answers "what is going on"
    /// before any glyph has to be read.
    var colour: NSColor {
        switch self {
        // Cool and receding: work in progress is the least of your worries.
        case .running: Brand.cyan
        // Warm and advancing. Brand orange is spent here and nowhere else,
        // because this is the one state the app exists for.
        case .waiting: Brand.orange
        case .stalled, .error: Brand.red
        case .done: Brand.green
        case .idle: Brand.idleBody
        }
    }

    var bodyColour: NSColor { colour }

    /// Beak and feet stay brand orange whatever the body is doing: hue is the
    /// state, but the silhouette and that orange beak are the identity.
    var beakColour: NSColor { self == .idle ? Brand.idleBeak : Brand.beak }

    var badgeColour: NSColor {
        switch self {
        case .running: .clear
        // A shade lighter than the grey body, so the z still reads.
        case .idle: Brand.idleBadge
        case .waiting, .stalled, .done, .error: colour
        }
    }
}

extension SessionState {
    /// How one session wears the mark.
    var face: MascotFace {
        switch self {
        case .running: .running
        case .done: .done
        // A prompt only a person can answer is a different kind of stop from a
        // tool that will not finish, and the badge is where that difference shows.
        case .blocked(let reason): reason.isImmediate ? .waiting : .stalled
        }
    }
}
