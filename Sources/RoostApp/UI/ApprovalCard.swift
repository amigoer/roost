import SwiftUI
import RoostCore

/// A tool call held at the gate, with the two answers that release it.
///
/// The buttons are laid out from `IslandGeometry.Approval`, the same numbers
/// the hit test uses, because the island itself is click-through and the click
/// arrives as a coordinate rather than as a press on a control.
struct ApprovalCard: View {
    let request: ApprovalRequest
    let hovered: IslandGeometry.ApprovalHit?

    var body: some View {
        HStack(spacing: 10) {
            MascotView(face: .waiting, cell: MascotView.small)

            VStack(alignment: .leading, spacing: 3) {
                (Text(request.tool).foregroundStyle(MascotFace.waiting.colour.swiftUI)
                    + Text("  wants to run in  ").foregroundStyle(Brand.textSecondary)
                    + Text(request.projectName).foregroundStyle(Brand.textPrimary))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Text(request.detail ?? "no arguments")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Brand.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            button("Deny", tint: Brand.red.swiftUI, active: hovered == .deny)
            button("Allow", tint: MascotFace.done.colour.swiftUI, active: hovered == .allow)
        }
        .padding(.leading, 12)
        .padding(.trailing, IslandGeometry.Approval.trailingInset)
        .frame(height: IslandGeometry.Approval.height)
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
    }
}
