import CoreGraphics

/// Size of the island for a given state.
///
/// Growth is the primary signal. The notch changing shape is unmistakable in
/// peripheral vision in a way a colour change is not, so only `blocked` earns
/// it: running and done stay at cutout size and just flank it with the mark.
public enum IslandGeometry {
    public static let expandedWidth: CGFloat = 470

    /// The held-tool-call card, which pushes the rows down while it is showing.
    public enum Approval {
        public static let height: CGFloat = 66
        public static let buttonWidth: CGFloat = 62
        public static let buttonHeight: CGFloat = 24
        public static let gap: CGFloat = 8
        public static let trailingInset: CGFloat = 14
    }

    public enum ApprovalHit: Sendable { case allow, deny }

    /// Vertical gap between the island's top and the first row, i.e. the header.
    public static func rowsTopInset(notch: CGSize, hasApproval: Bool = false) -> CGFloat {
        notch.height + 6 + (hasApproval ? Approval.height : 0)
    }

    /// Row index under a point given as distance from the island's top edge.
    public static func rowIndex(atOffsetFromTop offset: CGFloat, notch: CGSize, rowCount: Int,
                         hasApproval: Bool = false) -> Int? {
        let start = rowsTopInset(notch: notch, hasApproval: hasApproval)
        guard offset >= start else { return nil }
        let index = Int((offset - start) / rowHeight)
        return index < rowCount ? index : nil
    }

    /// Which button of the approval card a point lands on.
    ///
    /// The island paints nothing it can be clicked through, so the buttons are
    /// geometry on both sides: the card view lays them out from these same
    /// numbers, and drift between the two would mean clicking the wrong answer.
    public static func approvalHit(offsetFromTop y: CGFloat, offsetFromLeft x: CGFloat,
                            notch: CGSize, islandWidth: CGFloat) -> ApprovalHit? {
        let top = rowsTopInset(notch: notch)
        let buttonTop = top + (Approval.height - Approval.buttonHeight) / 2
        guard y >= buttonTop, y <= buttonTop + Approval.buttonHeight else { return nil }

        let allowStart = islandWidth - Approval.trailingInset - Approval.buttonWidth
        if x >= allowStart, x <= allowStart + Approval.buttonWidth { return .allow }
        let denyStart = allowStart - Approval.gap - Approval.buttonWidth
        if x >= denyStart, x <= denyStart + Approval.buttonWidth { return .deny }
        return nil
    }
    public static let rowHeight: CGFloat = 46
    public static let maxVisibleRows = 6

    /// Collapsed, the island always flanks the cutout with a status slot on the
    /// left and a count slot on the right, so it is never a blank black box.
    ///
    /// Dormant is the one exception: with no live sessions there is nothing to
    /// report, so the notch is left exactly as the hardware made it.
    public static func collapsedSize(level: SignalLevel, tier: EscalationTier, notch: CGSize) -> CGSize {
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

    public static func expandedSize(notch: CGSize, sessionCount: Int, hasFooter: Bool,
                             hasApproval: Bool = false) -> CGSize {
        let rows = max(1, min(sessionCount, maxVisibleRows))
        return CGSize(width: max(expandedWidth, notch.width + 160),
                      height: rowsTopInset(notch: notch, hasApproval: hasApproval)
                              + CGFloat(rows) * rowHeight + (hasFooter ? 24 : 0) + 10)
    }

    public static func size(level: SignalLevel, tier: EscalationTier, notch: CGSize,
                     expanded: Bool, sessionCount: Int, hasFooter: Bool = false,
                     hasApproval: Bool = false) -> CGSize {
        expanded
            ? expandedSize(notch: notch, sessionCount: sessionCount,
                           hasFooter: hasFooter, hasApproval: hasApproval)
            : collapsedSize(level: level, tier: tier, notch: notch)
    }

    public static func bottomRadius(level: SignalLevel, expanded: Bool) -> CGFloat {
        if expanded { return 26 }
        switch level {
        case .dormant: return NotchMetrics.lowerCornerRadius
        case .running, .done: return 13
        case .blocked: return 15
        }
    }
}
