import SwiftUI
import RoostCore

/// A plan waiting on a verdict, with as much of it as the island can hold.
///
/// Approving is letting `ExitPlanMode` run, which is what the terminal's own
/// plan prompt does; revising sends it back and leaves the session in plan mode.
/// The buttons are laid out from `IslandGeometry`, the same numbers the hit
/// test uses, because the island is click-through and a click arrives as a
/// coordinate rather than as a press on a control.
struct PlanCard: View {
    let request: ApprovalRequest
    let plan: String
    /// The conversation whose plan this is, by the name its row would use.
    let title: String?
    let hovered: IslandGeometry.ApprovalHit?
    let strings: Strings

    private var preview: PlanPreview.Preview {
        PlanPreview.make(plan, limit: IslandGeometry.Held.planLines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            lines(preview)
            buttons
            Color.clear.frame(height: IslandGeometry.Held.bottomPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            MascotView(face: .waiting, cell: MascotView.small)
            CardTitle(project: request.projectName, title: title)
            Text(strings.planChip)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(MascotFace.waiting.colour.swiftUI)
                .fixedSize()
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: IslandGeometry.Held.planHeaderHeight)
    }

    /// Fixed-height lines, so the buttons below stay exactly where the hit test
    /// says they are however short the plan turns out to be.
    private func lines(_ preview: PlanPreview.Preview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.textPrimary.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: IslandGeometry.Held.planLineHeight)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: CGFloat(IslandGeometry.Held.planLines) * IslandGeometry.Held.planLineHeight,
               alignment: .top)
    }

    private var buttons: some View {
        HStack(spacing: IslandGeometry.Approval.gap) {
            if preview.remaining > 0 {
                Text(strings.moreLines(preview.remaining))
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textTertiary)
            }
            Spacer(minLength: 8)
            button(strings.revise, tint: Brand.cyan.swiftUI, active: hovered == .deny)
            button(strings.approve, tint: MascotFace.done.colour.swiftUI, active: hovered == .allow)
        }
        .padding(.leading, 12)
        .padding(.trailing, IslandGeometry.Approval.trailingInset)
        .frame(height: IslandGeometry.Held.planButtonsHeight)
    }

    private func button(_ title: String, tint: Color, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? .black.opacity(0.88) : tint)
            .frame(width: IslandGeometry.Approval.buttonWidth,
                   height: IslandGeometry.Approval.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? tint : tint.opacity(0.14))
            )
            // The island is click-through, so a button lights up from a
            // coordinate rather than from a press. Fading rather than cutting
            // is what makes that read as the cursor being on it.
            .animation(.easeOut(duration: 0.14), value: active)
    }
}
