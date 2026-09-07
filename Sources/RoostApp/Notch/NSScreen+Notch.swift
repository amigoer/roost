import AppKit
import RoostCore

extension NSScreen {
    /// Stable across display reconfiguration, unlike `NSScreen` identity or index.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) == 1
    }

    /// Real menu bar height. `NSStatusBar.thickness` reports 22 even on a
    /// notched display where the bar is actually 32pt, so it is not usable here.
    var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }

    var notchRect: CGRect? {
        NotchMetrics.notchRect(auxiliaryTopLeft: auxiliaryTopLeftArea,
                               auxiliaryTopRight: auxiliaryTopRightArea)
    }

    var hasNotch: Bool { notchRect != nil }

    /// The notch when there is one, otherwise a centred stand-in of the same role.
    var signalAnchorRect: CGRect {
        notchRect ?? NotchMetrics.fallbackRect(screenFrame: frame,
                                               menuBarHeight: max(menuBarHeight, 24))
    }
}
