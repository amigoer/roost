import SwiftUI
import RoostCore

/// What the island shows while collapsed: the mascot left of the cutout and a
/// count right of it, mirroring the island idiom's icon/badge pairing.
struct CollapsedContent: View {
    let face: MascotFace
    let level: SignalLevel
    let sessionCount: Int
    let blockedCount: Int
    /// Shown in the count's place while a quota window is spent: there is
    /// nothing to count, and the clock is the whole of what is left to say.
    var countdown: String?
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            MascotView(face: face, animated: true)
                // Centred on the chick, not on its canvas. The badge corner is
                // empty in some faces, and centring the canvas would leave the
                // body sitting a few points further left in those.
                .offset(x: PixelChick.bodyCentringOffset(cell: MascotView.large))
                .frame(maxWidth: .infinity)
            // The physical cutout: nothing may be drawn here.
            Color.clear.frame(width: notchWidth)
            countBadge.frame(maxWidth: .infinity)
        }
    }

    /// A disc either way, and the same size as the chick opposite it: a bare
    /// digit weighs a third of what the mark does, and the strip goes visibly
    /// lopsided. What changes with state is the fill, not the footprint.
    private var countBadge: some View {
        Text(countdown ?? "\(level == .blocked ? blockedCount : sessionCount)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(level == .blocked ? .black.opacity(0.88) : Brand.textPrimary.opacity(0.62))
            .monospacedDigit()
            .padding(.horizontal, 5)
            // A capsule rather than a circle: at one digit they are the same
            // shape, and at two the circle is inscribed in the frame and the
            // number hangs out of both sides of it.
            .frame(minWidth: 17, minHeight: 17)
            .background(
                // The badge's colour rather than the body's. They are the same
                // for every face but the spent one, whose body is grey because
                // nothing is running and whose badge is what makes that urgent.
                Capsule().fill(level == .blocked ? face.badgeColour.swiftUI : Color.white.opacity(0.13))
            )
    }
}
