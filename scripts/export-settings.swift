import AppKit
import SwiftUI
import RoostCore

/// Renders the settings window's content to a PNG, so the screenshots in the
/// readme are generated from the real view rather than captured by hand and
/// left to drift.
///
/// Draws through AppKit itself -- no screen recording permission, no window
/// server, no cursor in the frame -- which is also what makes it produce the
/// same image on any machine.
///
/// Run it through `scripts/settings-screenshots.sh`, which compiles this
/// against the app's own sources and writes both languages.
@main
enum ExportSettings {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 else {
            FileHandle.standardError.write(
                Data("usage: export-settings <version> <en.png> <zh.png>\n".utf8))
            exit(2)
        }

        // Never in the Dock and never in front: this draws, it does not appear.
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        render(.english, version: arguments[0], to: arguments[1])
        render(.chinese, version: arguments[0], to: arguments[2])
        exit(0)
    }

    @MainActor
    static func render(_ language: LanguageChoice, version: String, to path: String) {
        let model = RoostModel()
        model.languageChoice = language
        // A throwaway binary's bundle is not the app's, and a screenshot that
        // says "Version 0" helps nobody.
        model.currentVersion = version

        // The whole form, not the window's worth of it. On screen the rest is
        // a scroll away; in a readme it would just be missing.
        let host = NSHostingView(
            rootView: SettingsView(model: model) { _ in }
                .frame(width: SettingsView.size.width))
        host.frame = NSRect(origin: .zero,
                            size: NSSize(width: SettingsView.size.width, height: 100))
        let size = NSSize(width: SettingsView.size.width,
                          height: host.fittingSize.height.rounded(.up))
        host.frame = NSRect(origin: .zero, size: size)

        // A window is what gives the view its backing scale and its materials.
        // Without one the grouped form draws flat and the switches lose their
        // fill.
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // Twice the points in each direction, with the rep still measured in
        // points, is what makes this a retina image rather than a large blurry
        // one.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { fatalError("could not make a bitmap") }
        rep.size = size

        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil
        else { fatalError("could not write \(path)") }
        print("\(path)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}
