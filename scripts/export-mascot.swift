import AppKit
import RoostCore

/// Renders every face of the mascot to a PNG, so the table in the readme is
/// drawn from the same grid the app draws from rather than exported by hand and
/// left to drift a face behind.
///
/// Checks the art before it draws any of it: a badge that touches the chick is
/// refused rather than exported, because on the faces where the two share a
/// colour it is not visible as a mistake in the result -- it just looks like a
/// differently shaped chick.
///
/// Draws through AppKit itself -- no screen recording permission, no window
/// server -- which is also what makes it produce the same image on any machine.
///
/// Run it through `scripts/mascot-images.sh`, which compiles this against the
/// app's own sources.
@main
enum ExportMascot {
    /// Points per art cell. Sixteen puts a face at 240x176, which is what the
    /// readme has always shown them at.
    static let cell: CGFloat = 16

    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let directory = arguments.first else {
            FileHandle.standardError.write(Data("usage: export-mascot <directory>\n".utf8))
            exit(2)
        }

        let contacts = badgeContacts()
        guard contacts.isEmpty else {
            for contact in contacts {
                FileHandle.standardError.write(Data("\(contact)\n".utf8))
            }
            FileHandle.standardError.write(Data("badge touches the chick; nothing exported\n".utf8))
            exit(1)
        }

        for face in MascotFace.allCases {
            let url = URL(fileURLWithPath: directory).appending(path: "\(face.rawValue).png")
            guard let data = png(face) else {
                FileHandle.standardError.write(Data("could not render \(face.rawValue)\n".utf8))
                exit(1)
            }
            try? data.write(to: url)
            print(url.lastPathComponent)
        }
    }

    /// The empty bottom row is dropped rather than drawn: it is there so the
    /// running hop has somewhere to land, and it is whitespace in a readme.
    private static func png(_ face: MascotFace) -> Data? {
        let size = CGSize(width: CGFloat(PixelChick.columns) * cell,
                          height: CGFloat(PixelChick.rows - 1) * cell)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width),
                                            pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        for (token, colour) in inks(face) {
            cg.addPath(PixelChick.path(token, face: face, cell: cell,
                                       origin: CGPoint(x: 0, y: -cell)))
            cg.setFillColor(colour.cgColor)
            cg.fillPath()
        }
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    /// Every place a badge cell lands on, or beside, a cell of the chick --
    /// through every pose and every offset a face can reach.
    ///
    /// The body rides a beat's offset and the badge does not, so the two are
    /// compared where they actually land rather than where they are written.
    /// Diagonals are allowed: a corner touch still reads as two shapes.
    private static func badgeContacts() -> [String] {
        var contacts: [String] = []
        for face in MascotFace.allCases {
            let clip = PixelChick.clip(face)
            for (index, beat) in (clip.arrival + clip.loop).enumerated() {
                var body: Set<[Int]> = []
                var badge: Set<[Int]> = []
                for (row, line) in beat.grid.enumerated() {
                    for (column, character) in line.enumerated() {
                        switch character {
                        case "B", "K", "E": body.insert([row - beat.dy, column + beat.dx])
                        case "A": badge.insert([row, column])
                        default: break
                        }
                    }
                }
                for cell in badge.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                    let around = [cell, [cell[0] - 1, cell[1]], [cell[0] + 1, cell[1]],
                                  [cell[0], cell[1] - 1], [cell[0], cell[1] + 1]]
                    for touched in around where body.contains(touched) {
                        contacts.append("\(face.rawValue) beat \(index): badge "
                                        + "r\(cell[0])c\(cell[1]) meets body "
                                        + "r\(touched[0])c\(touched[1])")
                    }
                }
            }
        }
        return contacts
    }

    private static func inks(_ face: MascotFace) -> [(Character, NSColor)] {
        [("B", face.bodyColour), ("K", face.beakColour), ("E", Brand.eye),
         ("S", Brand.cyan), ("A", face.badgeColour)]
    }
}
