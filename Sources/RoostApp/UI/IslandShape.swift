import SwiftUI
import RoostCore

/// The island silhouette: square on top because it sits flush with the screen
/// edge, rounded below so drawn pixels and the physical cutout read as one shape.
struct IslandShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0,
                               bottomLeading: bottomRadius,
                               bottomTrailing: bottomRadius,
                               topTrailing: 0)
        ).path(in: rect)
    }

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
}

/// Size of the island for a given state.
///
/// Growth is the primary signal. The notch changing shape is unmistakable in
/// peripheral vision in a way a colour change is not, so only `blocked` earns
/// it: running and done stay at cutout size and just flank it with the mark.
enum IslandGeometry {
    static let expandedWidth: CGFloat = 420

    /// Vertical gap between the island's top and the first row, i.e. the header.
    static func rowsTopInset(notch: CGSize) -> CGFloat { notch.height + 6 }

    /// Row index under a point given as distance from the island's top edge.
    static func rowIndex(atOffsetFromTop offset: CGFloat, notch: CGSize, rowCount: Int) -> Int? {
        let start = rowsTopInset(notch: notch)
        guard offset >= start else { return nil }
        let index = Int((offset - start) / rowHeight)
        return index < rowCount ? index : nil
    }
    static let rowHeight: CGFloat = 46
    static let maxVisibleRows = 6

    /// Collapsed, the island always flanks the cutout with a status slot on the
    /// left and a count slot on the right, so it is never a blank black box.
    ///
    /// Dormant is the one exception: with no live sessions there is nothing to
    /// report, so the notch is left exactly as the hardware made it.
    static func collapsedSize(level: SignalLevel, tier: EscalationTier, notch: CGSize) -> CGSize {
        switch level {
        case .dormant:
            notch
        case .running, .done:
            CGSize(width: notch.width + 78, height: notch.height)
        case .blocked:
            // Escalation grows width only. Height stays flush with the cutout so
            // the island never hangs below the menu bar, and widening happens to
            // be the lever peripheral-display research favours anyway.
            CGSize(width: notch.width + (tier == .calm ? 104 : 132),
                   height: notch.height)
        }
    }

    static func expandedSize(notch: CGSize, sessionCount: Int, hasFooter: Bool) -> CGSize {
        let rows = max(1, min(sessionCount, maxVisibleRows))
        return CGSize(width: max(expandedWidth, notch.width + 160),
                      height: notch.height + 6 + CGFloat(rows) * rowHeight
                              + (hasFooter ? 24 : 0) + 10)
    }

    static func size(level: SignalLevel, tier: EscalationTier, notch: CGSize,
                     expanded: Bool, sessionCount: Int, hasFooter: Bool = false) -> CGSize {
        expanded
            ? expandedSize(notch: notch, sessionCount: sessionCount, hasFooter: hasFooter)
            : collapsedSize(level: level, tier: tier, notch: notch)
    }

    static func bottomRadius(level: SignalLevel, expanded: Bool) -> CGFloat {
        if expanded { return 26 }
        switch level {
        case .dormant: return NotchMetrics.lowerCornerRadius
        case .running, .done: return 13
        case .blocked: return 15
        }
    }
}
