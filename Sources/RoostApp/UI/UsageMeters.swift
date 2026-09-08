import SwiftUI
import RoostCore

/// What is left of the quota windows, along the footer.
///
/// Cells rather than a smooth bar, on the same grid the chick and the agent
/// marks are drawn on: a fill answers "how close to full" without being read,
/// and in this idiom it answers "how many left" as well, which is countable in
/// a way a capsule is not. Colour is the same three-step scale the mascot uses,
/// so getting tight looks here as it looks anywhere else in the island.
struct UsageMeters: View {
    let usage: Usage
    let strings: Strings

    /// Past this, the useful number stops being how much is gone and starts
    /// being when it comes back.
    static let tight = 0.8

    private static let cells = 10
    private static let cellSize = CGSize(width: 3, height: 5)
    private static let cellGap: CGFloat = 1

    private var fresh: Bool { usage.isFresh() }

    var body: some View {
        HStack(spacing: 9) {
            if fresh {
                if let window = usage.fiveHour {
                    meter(strings.fiveHour, window, countdownWhenTight: true)
                }
                if let window = usage.sevenDay {
                    meter(strings.sevenDay, window, countdownWhenTight: false)
                }
            } else if let binding = usage.binding {
                // Nothing has reported for a while. One window instead of two,
                // because what matters about a stale reading is less its second
                // decimal than the hour it was taken.
                meter(label(binding.label), binding.window, countdownWhenTight: false)
                Text(strings.asOf(usage.reportedAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Brand.textTertiary)
                    .fixedSize()
            }
        }
        .opacity(fresh ? 1 : 0.55)
        .frame(width: IslandGeometry.Footer.metersWidth, alignment: .trailing)
    }

    private func label(_ window: Usage.WindowLabel) -> String {
        window == .fiveHour ? strings.fiveHour : strings.sevenDay
    }

    /// Only the five-hour window earns a countdown. The seven-day one resets on
    /// a horizon nobody is waiting out, and two countdowns do not fit anyway.
    private func meter(_ label: String, _ window: UsageWindow,
                       countdownWhenTight: Bool) -> some View {
        let turned = usage.hasReset(window)
        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.textTertiary)

            track(window, emptied: turned)

            Text(trailing(window, turned: turned, countdownWhenTight: countdownWhenTight))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(turned ? Brand.textTertiary : colour(window.used).swiftUI)
                .monospacedDigit()
                .fixedSize()
        }
    }

    /// Rounded up, so a window somebody has started spending never reads as
    /// untouched: the first cell is the difference between "none yet" and
    /// "begun", and that is the one comparison this is for.
    private func track(_ window: UsageWindow, emptied: Bool) -> some View {
        let filled = emptied ? 0 : Int((window.used * Double(Self.cells)).rounded(.up))
        return HStack(spacing: Self.cellGap) {
            ForEach(0..<Self.cells, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? colour(window.used).swiftUI : .white.opacity(0.12))
                    .frame(width: Self.cellSize.width, height: Self.cellSize.height)
            }
        }
    }

    private func trailing(_ window: UsageWindow, turned: Bool,
                          countdownWhenTight: Bool) -> String {
        // The window came back while nobody was reporting. What has gone on it
        // since is unknown, and showing that as zero would be a guess.
        if turned { return strings.windowReset }
        guard countdownWhenTight, window.used >= Self.tight,
              let remaining = window.remaining() else { return strings.percent(window.used) }
        return strings.resetsIn(Int(remaining))
    }

    private func colour(_ used: Double) -> NSColor {
        switch used {
        case ..<0.5: Brand.idleBadge
        case ..<Self.tight: Brand.orange
        default: Brand.red
        }
    }
}

/// The same figures with the times spelled out, while the cursor is on them.
///
/// A line rather than a popover: the footer is already a line, the height does
/// not change, and nothing here is worth a second surface to read. It takes the
/// whole strip because a reset time is the sort of thing that gets truncated
/// into uselessness by two characters.
struct UsageDetail: View {
    let usage: Usage
    let strings: Strings

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if !usage.isFresh() {
                part(strings.asOf(usage.reportedAt), Brand.textTertiary)
            }
            if let window = usage.fiveHour {
                part(line(strings.fiveHour, window, onTheHour: true), tint(window))
            }
            if let window = usage.sevenDay {
                part(line(strings.sevenDay, window, onTheHour: false), tint(window))
            }
            // Only the reading that comes from Anthropic knows these, and they
            // explain a seven-day figure rather than standing beside it.
            ForEach(usage.scoped, id: \.label) { scoped in
                part("\(scoped.label) \(strings.percent(scoped.window.used))", Brand.textTertiary)
            }
        }
    }

    private func part(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(colour)
            .monospacedDigit()
            .fixedSize()
    }

    private func line(_ label: String, _ window: UsageWindow, onTheHour: Bool) -> String {
        let figure = "\(label) \(strings.percent(window.used))"
        guard let resets = window.resetsAt else { return figure }
        if usage.hasReset(window) { return "\(label) \(strings.windowReset)" }
        return "\(figure) · \(onTheHour ? strings.resetsAt(resets) : strings.resetsOn(resets))"
    }

    private func tint(_ window: UsageWindow) -> Color {
        usage.hasReset(window) ? Brand.textTertiary : Brand.textSecondary
    }
}
