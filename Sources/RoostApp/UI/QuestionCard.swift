import SwiftUI
import RoostCore

/// A question a session asked, with its answers as rows.
///
/// Full-width rows rather than a strip of buttons: an option label is a
/// sentence often enough that a fixed-width button would truncate the very
/// thing being chosen. The rows are laid out from `IslandGeometry.Held`, the
/// same numbers the hit test uses, because the island is click-through and a
/// click arrives as a coordinate rather than as a press on a control.
struct QuestionCard: View {
    let request: ApprovalRequest
    let question: HeldQuestion
    /// The conversation asking, by the name its row would use.
    let title: String?
    let hoveredOption: Int?
    let strings: Strings

    private var options: [HeldQuestion.Option] {
        Array(question.options.prefix(ApprovalGate.maxOptions))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            prompt
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                answer(option, active: hoveredOption == index)
            }
            Color.clear.frame(height: IslandGeometry.Held.bottomPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which session is asking, then what it asked -- in the shape a row uses,
    /// so the card and the list never name the same session two ways. The
    /// question's own header rides the second line as the lede, where a row
    /// carries what a session is doing.
    private var prompt: some View {
        HStack(spacing: 10) {
            MascotView(face: .waiting, cell: MascotView.small)

            VStack(alignment: .leading, spacing: 2) {
                CardTitle(project: request.projectName, title: title)

                HStack(spacing: 6) {
                    Text(question.header ?? strings.questionChip)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MascotFace.waiting.colour.swiftUI)
                        .fixedSize()
                    Text(question.prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textPrimary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: IslandGeometry.Held.promptHeight)
    }

    private func answer(_ option: HeldQuestion.Option, active: Bool) -> some View {
        HStack(spacing: 8) {
            Text(option.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? .black.opacity(0.88) : Brand.textPrimary)
                .fixedSize()

            if let description = option.description {
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(active ? .black.opacity(0.62) : Brand.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(height: IslandGeometry.Held.optionHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(active ? MascotFace.waiting.colour.swiftUI : Color.white.opacity(0.05))
                .padding(.horizontal, 6)
        )
        // The island is click-through, so an answer lights up from a coordinate
        // rather than from a press. Fading rather than cutting is what makes
        // that read as the cursor being on it.
        .animation(.easeOut(duration: 0.14), value: active)
    }
}

/// A held call's first line: the project, then the conversation.
///
/// The same shape a row uses, because they are the same session. A card that
/// named only the project left the reader to find out whose question it was
/// from a row underneath it, which is the wrong way round -- the card is the
/// thing being answered.
struct CardTitle: View {
    let project: String
    let title: String?

    var body: some View {
        (Text(project).foregroundStyle(Brand.textSecondary)
            + Text(title.map { " · \($0)" } ?? "").foregroundStyle(Brand.textPrimary))
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
