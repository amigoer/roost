import AppKit
import SwiftUI

/// The palette from the mascot design sheet.
///
/// The chick's body is brand orange in every live state and grey only when
/// idle: state is carried by the face and the corner badge, never by the hue.
///
/// Computed rather than stored because `NSColor` is not `Sendable`, so a
/// `static let` would not survive strict concurrency checking. `NSColor` for
/// the art layers, `Color` for the panel's text.
enum Brand {
    static var orange: NSColor { hex(0xFF9F0A) }
    static var beak: NSColor { hex(0xCF6A00) }
    static var eye: NSColor { hex(0x1C1206) }
    static var green: NSColor { hex(0x30D158) }
    static var red: NSColor { hex(0xFF453A) }
    static var sweat: NSColor { hex(0x64D2FF) }

    static var idleBody: NSColor { hex(0x8E8E93) }
    static var idleBeak: NSColor { hex(0x6F7076) }
    static var idleBadge: NSColor { hex(0x9A9CA3) }

    static var accent: Color { orange.swiftUI }
    static var textPrimary: Color { hex(0xF2F2F4).swiftUI }
    static var textSecondary: Color { hex(0x9A9CA3).swiftUI }
    static var textTertiary: Color { hex(0x7F818A).swiftUI }

    static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1)
    }
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }
}
