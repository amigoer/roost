import CoreGraphics

/// Pure notch geometry, kept free of AppKit so it can be unit tested.
public enum NotchMetrics {
    /// Corner radii of the physical cutout, measured by Iconfactory's Notchmeister.
    public static let upperCornerRadius: CGFloat = 4
    public static let lowerCornerRadius: CGFloat = 8

    /// Width used when faking a notch on a display that has none.
    public static let fallbackWidth: CGFloat = 185

    /// Derives the notch rect from the two menu bar areas flanking it.
    ///
    /// Deliberately measured from the gap between the areas rather than
    /// `screenWidth - left - right`: the latter drifts on scaled displays.
    /// Returns nil when either area is missing, which is how AppKit reports
    /// a display with no notch.
    public static func notchRect(auxiliaryTopLeft left: CGRect?,
                                 auxiliaryTopRight right: CGRect?) -> CGRect? {
        guard let left, let right else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return CGRect(x: left.maxX,
                      y: min(left.minY, right.minY),
                      width: width,
                      height: max(left.height, right.height))
    }

    /// Stand-in strip for notch-less displays, centred where a notch would be.
    public static func fallbackRect(screenFrame: CGRect, menuBarHeight: CGFloat) -> CGRect {
        CGRect(x: screenFrame.midX - fallbackWidth / 2,
               y: screenFrame.maxY - menuBarHeight,
               width: fallbackWidth,
               height: menuBarHeight)
    }
}
