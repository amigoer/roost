import CoreGraphics

/// Size of the island for a given state.
///
/// Growth is the primary signal. The notch changing shape is unmistakable in
/// peripheral vision in a way a colour change is not, so only `blocked` earns
/// it: running and done stay at cutout size and just flank it with the mark.
public enum IslandGeometry {
    public static let expandedWidth: CGFloat = 470

    /// The held call, which pushes the rows down while it is showing.
    ///
    /// Its height depends on what is being asked: a permission is one line and
    /// two buttons, a question is a line and one row per answer.
    public enum Held {
        public static let permissionHeight: CGFloat = 66
        /// The two lines a question puts above its answers: which session is
        /// asking, then what it asked.
        public static let promptHeight: CGFloat = 40
        /// One answer.
        public static let optionHeight: CGFloat = 26
        public static let bottomPadding: CGFloat = 6

        public static func height(_ kind: HeldKind?) -> CGFloat {
            switch kind {
            case nil: 0
            case .permission: permissionHeight
            case .question(let question):
                promptHeight
                    + CGFloat(min(question.options.count, ApprovalGate.maxOptions)) * optionHeight
                    + bottomPadding
            }
        }
    }

    /// The permission card's two buttons.
    public enum Approval {
        public static let buttonWidth: CGFloat = 62
        public static let buttonHeight: CGFloat = 24
        public static let gap: CGFloat = 8
        public static let trailingInset: CGFloat = 14
    }

    public enum ApprovalHit: Sendable { case allow, deny }

    /// The collapsed strip, measured from the cutout outwards.
    ///
    /// Both flanks carry the same slot so the island stays symmetric whatever
    /// is standing in them, and the numbers are tight: at rest this is a strip
    /// hugging the cutout, not a bar with the cutout somewhere inside it.
    public enum Collapsed {
        public static let slot: CGFloat = 20
        public static let gap: CGFloat = 9
        public static let margin: CGFloat = 6
        public static let flank: CGFloat = slot + gap + margin
    }

    /// The menu button in the header.
    ///
    /// The app has no Dock icon and no menu bar item, so without something
    /// visible here the only way to reach the menu -- including Quit -- is a
    /// right-click nobody can see.
    public enum Menu {
        public static let buttonSize: CGFloat = 20
        public static let trailingInset: CGFloat = 14
    }

    /// Whether a point lands on the header's menu button.
    public static func menuHit(offsetFromTop y: CGFloat, offsetFromLeft x: CGFloat,
                               notch: CGSize, islandWidth: CGFloat) -> Bool {
        guard y >= 0, y <= notch.height else { return false }
        let start = islandWidth - Menu.trailingInset - Menu.buttonSize
        return x >= start && x <= start + Menu.buttonSize
    }

    /// Where the held call starts: directly under the header, whatever it is.
    public static func heldTop(notch: CGSize) -> CGFloat { notch.height + 6 }

    /// Vertical gap between the island's top and the first row.
    public static func rowsTopInset(notch: CGSize, heldHeight: CGFloat = 0) -> CGFloat {
        heldTop(notch: notch) + heldHeight
    }

    /// Row index under a point given as distance from the island's top edge.
    public static func rowIndex(atOffsetFromTop offset: CGFloat, notch: CGSize, rowCount: Int,
                                heldHeight: CGFloat = 0) -> Int? {
        let start = rowsTopInset(notch: notch, heldHeight: heldHeight)
        guard offset >= start else { return nil }
        let index = Int((offset - start) / rowHeight)
        return index < rowCount ? index : nil
    }

    /// Which button of the permission card a point lands on.
    ///
    /// The island paints nothing it can be clicked through, so the buttons are
    /// geometry on both sides: the card view lays them out from these same
    /// numbers, and drift between the two would mean clicking the wrong answer.
    public static func approvalHit(offsetFromTop y: CGFloat, offsetFromLeft x: CGFloat,
                                   notch: CGSize, islandWidth: CGFloat) -> ApprovalHit? {
        let top = heldTop(notch: notch)
        let buttonTop = top + (Held.permissionHeight - Approval.buttonHeight) / 2
        guard y >= buttonTop, y <= buttonTop + Approval.buttonHeight else { return nil }

        let allowStart = islandWidth - Approval.trailingInset - Approval.buttonWidth
        if x >= allowStart, x <= allowStart + Approval.buttonWidth { return .allow }
        let denyStart = allowStart - Approval.gap - Approval.buttonWidth
        if x >= denyStart, x <= denyStart + Approval.buttonWidth { return .deny }
        return nil
    }

    /// Which answer of a question card a point lands on.
    ///
    /// Answers are full-width rows rather than buttons in a strip: an option
    /// label is a sentence often enough that a fixed-width button would have to
    /// truncate the thing being chosen.
    public static func optionIndex(offsetFromTop y: CGFloat, notch: CGSize,
                                   optionCount: Int) -> Int? {
        let start = heldTop(notch: notch) + Held.promptHeight
        guard y >= start else { return nil }
        let index = Int((y - start) / Held.optionHeight)
        return index < min(optionCount, ApprovalGate.maxOptions) ? index : nil
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
            CGSize(width: notch.width + 2 * Collapsed.flank, height: notch.height)
        case .blocked:
            // Escalation grows width only. Height stays flush with the cutout so
            // the island never hangs below the menu bar, and widening happens to
            // be the lever peripheral-display research favours anyway.
            CGSize(width: notch.width + 2 * (Collapsed.flank + (tier == .calm ? 13 : 27)),
                   height: notch.height)
        }
    }

    public static func expandedSize(notch: CGSize, sessionCount: Int, hasFooter: Bool,
                                    heldHeight: CGFloat = 0) -> CGSize {
        let rows = max(1, min(sessionCount, maxVisibleRows))
        return CGSize(width: max(expandedWidth, notch.width + 160),
                      height: rowsTopInset(notch: notch, heldHeight: heldHeight)
                              + CGFloat(rows) * rowHeight + (hasFooter ? 24 : 0) + 10)
    }

    public static func size(level: SignalLevel, tier: EscalationTier, notch: CGSize,
                            expanded: Bool, sessionCount: Int, hasFooter: Bool = false,
                            heldHeight: CGFloat = 0) -> CGSize {
        expanded
            ? expandedSize(notch: notch, sessionCount: sessionCount,
                           hasFooter: hasFooter, heldHeight: heldHeight)
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
