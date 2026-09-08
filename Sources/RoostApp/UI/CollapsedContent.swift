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
            MascotView(face: face)
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

    /// The count, and a disc under it only where the disc is the alarm.
    ///
    /// Filled, on `blocked`, it is the same escalation the mascot's badge is
    /// making in the same colour, and black on that colour is what carries a
    /// single digit across a room. Everywhere else it was a chip drawn around a
    /// number nobody is being asked to act on: weight the strip did not need,
    /// spent competing with the one mark that is meant to hold the eye. The
    /// digit alone carries a quiet state, one size up to make up the footprint.
    @ViewBuilder
    private var countBadge: some View {
        if let countdown {
            // A clock is not a count. Four or five characters do not fit a disc
            // that fits the strip -- it wrapped onto two lines and clipped
            // against the notch -- and a window running out is not a thing to
            // put a badge around anyway. Red text says it on its own.
            Text(countdown)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(face.badgeColour.swiftUI)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        } else {
            let count = "\(level == .blocked ? blockedCount : sessionCount)"
            Text(count)
                .font(.system(size: level == .blocked ? 11 : 12,
                              weight: .semibold, design: .rounded))
                .foregroundStyle(level == .blocked ? .black.opacity(0.88)
                                                   : Brand.textPrimary.opacity(0.72))
                .monospacedDigit()
                // The digit rolls rather than cuts. A session ending changes
                // this number and nothing else on the strip, and a figure that
                // swapped in place is a change nobody catches out of the corner
                // of an eye.
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.28), value: count)
                .padding(.horizontal, 5)
                // A capsule rather than a circle: at one digit they are the
                // same shape, and at two the circle is inscribed in the frame
                // and the number hangs out of both sides of it.
                .frame(minWidth: 17, minHeight: 17)
                .background {
                    if level == .blocked {
                        // The badge's colour rather than the body's: they are
                        // the same for every face but the spent one, whose body
                        // is grey because nothing is running.
                        Capsule().fill(face.badgeColour.swiftUI)
                    }
                }
        }
    }
}
