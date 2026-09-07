import SwiftUI
import RoostCore

struct SessionRowView: View {
    let session: Session
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 9) {
            MascotView(face: session.state.face, cell: MascotView.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 12.5, weight: isBlocked ? .semibold : .medium))
                    .foregroundStyle(Brand.textPrimary.opacity(nameOpacity))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    Text(session.projectName)
                    Text("·").opacity(0.6)
                    Text(statusText)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if isBlocked {
                // How long it has been stuck is the one number worth reading
                // here, so it gets the accent and nothing else does.
                Text(elapsed)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.accent)
                    .monospacedDigit()
            } else if isHovered {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
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

    private var statusText: String {
        switch session.state {
        case .blocked(let reason): label(for: reason)
        case .running: session.activity.map { "running \($0)" } ?? "working"
        case .done: "done"
        }
    }

    private func label(for reason: BlockReason) -> String {
        switch reason {
        case .permissionPrompt(let tool): tool.map { "needs permission: \($0)" } ?? "needs permission"
        case .question: "asked you a question"
        case .planApproval: "waiting on plan approval"
        case .agentNeedsInput(let label): label.map { "\($0) needs input" } ?? "needs input"
        case .stalledTool(let name): "stalled on \(name)"
        }
    }

    private var elapsed: String {
        let seconds = Int(session.blockedFor)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m\(String(format: "%02d", seconds % 60))s" }
        return "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
    }
}
