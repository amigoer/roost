import SwiftUI
import RoostCore

/// What the island shows while collapsed: the mascot left of the cutout and a
/// count right of it, mirroring the island idiom's icon/badge pairing.
struct CollapsedContent: View {
    let face: MascotFace
    let level: SignalLevel
    let sessionCount: Int
    let blockedCount: Int
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            MascotView(face: face, animated: true)
                .frame(maxWidth: .infinity)
            // The physical cutout: nothing may be drawn here.
            Color.clear.frame(width: notchWidth)
            countBadge.frame(maxWidth: .infinity)
        }
    }

    /// Filled in the mascot's colour only when something is blocked. Running
    /// and done keep the quiet translucent disc: a count nobody has to act on
    /// should not be the brightest thing on the strip.
    private var countBadge: some View {
        Text("\(level == .blocked ? blockedCount : sessionCount)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(level == .blocked ? .black.opacity(0.88) : Brand.textPrimary.opacity(0.6))
            .monospacedDigit()
            .frame(minWidth: 17, minHeight: 17)
            .background(
                Circle().fill(level == .blocked ? face.colour.swiftUI : Color.white.opacity(0.13))
            )
    }
}
