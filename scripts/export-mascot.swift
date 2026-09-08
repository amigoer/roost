import AppKit
import RoostCore

/// Renders every face of the mascot to a PNG, so the table in the readme is
/// drawn from the same grid the app draws from rather than exported by hand and
/// left to drift a face behind.
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

    private static func inks(_ face: MascotFace) -> [(Character, NSColor)] {
        [("B", face.bodyColour), ("K", face.beakColour), ("E", Brand.eye),
         ("S", Brand.cyan), ("A", face.badgeColour)]
    }
}
