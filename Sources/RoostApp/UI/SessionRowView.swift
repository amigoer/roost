import SwiftUI
import RoostCore

/// One session: whose it is, which conversation, what it is doing right now,
/// how it is doing, and for how long.
struct SessionRowView: View {
    let session: Session
    let isHovered: Bool
    let strings: Strings

    var body: some View {
        HStack(spacing: 10) {
            AgentMarkView(kind: session.agent)

            VStack(alignment: .leading, spacing: 2) {
                title
                activity
            }

            Spacer(minLength: 8)

            if let model = session.model {
                Text(model)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Brand.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(.white.opacity(0.06)))
                    .fixedSize()
            }

            MascotView(face: face, cell: MascotView.small)

            Text(elapsed)
                .font(.system(size: 10.5, weight: isBlocked ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isBlocked ? face.colour.swiftUI : Brand.textTertiary)
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: IslandGeometry.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.07) : .clear)
                .padding(.horizontal, 6)
        )
    }

    /// Project first: which repo it is answers "do I care" faster than the
    /// conversation's own title does.
    private var title: some View {
        (Text(session.projectName).foregroundStyle(Brand.textSecondary)
            + Text(" · ").foregroundStyle(Brand.textSecondary.opacity(0.5))
            + Text(session.name).foregroundStyle(Brand.textPrimary.opacity(nameOpacity)))
            .font(.system(size: 12, weight: isBlocked ? .semibold : .medium))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// What it is doing, in the session's own words: the tool and the argument
    /// a person would recognise.
    private var activity: some View {
        HStack(spacing: 6) {
            if let lede {
                Text(lede)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(face.colour.swiftUI)
                    .fixedSize()
            }
            if let trail = session.detail ?? fallbackTrail {
                Text(trail)
                    .font(.system(size: 10.5, design: lede == nil ? .default : .monospaced))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var face: MascotFace { session.state.face }

    private var isBlocked: Bool {
        if case .blocked = session.state { true } else { false }
    }

    private var nameOpacity: Double {
        switch session.state {
        case .blocked: 1.0
        case .running: 0.92
        case .done: 0.55
        }
    }

    private var lede: String? {
        switch session.state {
        case .blocked(let reason): strings.label(for: reason)
        case .running: session.activity ?? strings.working
        case .done: nil
        }
    }

    private var fallbackTrail: String? {
        if case .done = session.state { return strings.turnEnded }
        return nil
    }

    /// Blocked rows count how long they have been stuck; everything else counts
    /// how long since anything happened, which is what makes a stale one obvious.
    private var elapsed: String {
        strings.elapsed(Int(isBlocked ? session.blockedFor
                                      : Date().timeIntervalSince(session.lastActivityAt)))
    }
}
