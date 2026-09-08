import SwiftUI
import RoostCore

/// What is left of the quota windows, along the footer.
///
/// A bar and not just a figure: the question is how close the window is to
/// full, and a fill answers that without having to be read. The colour is the
/// same three-step scale the mascot uses, so "getting tight" looks the same
/// here as it does anywhere else in the island.
struct UsageMeters: View {
    let usage: Usage
    let strings: Strings

    /// Past this, the useful number stops being how much is gone and starts
    /// being when it comes back.
    private static let tight = 0.8

    private static let barWidth: CGFloat = 26
    private static let barHeight: CGFloat = 3.5

    var body: some View {
        HStack(spacing: 9) {
            if let window = usage.fiveHour {
                meter(strings.fiveHour, window, countdownWhenTight: true)
            }
            if let window = usage.sevenDay {
                meter(strings.sevenDay, window, countdownWhenTight: false)
            }
        }
    }

    /// Only the five-hour window earns a countdown. The seven-day one resets on
    /// a horizon nobody is waiting out, and two countdowns do not fit anyway.
    private func meter(_ label: String, _ window: UsageWindow,
                       countdownWhenTight: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.textTertiary)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(colour(window.used).swiftUI)
                    .frame(width: max(2, Self.barWidth * window.used))
            }
            .frame(width: Self.barWidth, height: Self.barHeight)

            Text(trailing(window, countdownWhenTight: countdownWhenTight))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colour(window.used).swiftUI)
                .monospacedDigit()
                .fixedSize()
        }
    }

    private func trailing(_ window: UsageWindow, countdownWhenTight: Bool) -> String {
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
