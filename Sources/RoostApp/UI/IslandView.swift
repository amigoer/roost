import SwiftUI
import RoostCore

/// The island: collapsed it is the signal, expanded it is the session list.
///
/// Design rule this file enforces: growth belongs to `.blocked` alone. The
/// mascot's own motion is a one-cell hop while running and a blinking badge
/// while blocked, so a change of *shape* at the notch still carries exactly one
/// meaning and never has to be interpreted.
struct IslandView: View {
    @Bindable var model: RoostModel
    /// Physical cutout size: the island's resting shape and the camera gap.
    let notchSize: CGSize

    private var size: CGSize {
        IslandGeometry.size(level: model.level,
                            tier: model.tier,
                            notch: notchSize,
                            expanded: model.isExpanded,
                            sessionCount: model.visibleSessions.count,
                            hasFooter: model.staleCount > 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var island: some View {
        if model.level == .dormant && !model.isExpanded {
            Color.clear.frame(width: notchSize.width, height: notchSize.height)
        } else {
            ZStack {
                IslandShape(bottomRadius: IslandGeometry.bottomRadius(level: model.level,
                                                                     expanded: model.isExpanded))
                    .fill(.black)
                    .shadow(color: .black.opacity(0.55), radius: 8, y: 3)


                if model.isExpanded {
                    expandedContent
                } else {
                    CollapsedContent(face: model.face,
                                     level: model.level,
                                     sessionCount: model.visibleSessions.count,
                                     blockedCount: model.blockedCount,
                                     notchWidth: notchSize.width)
                }
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.24, dampingFraction: 0.74), value: model.isExpanded)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.level)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.tier)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.bottom, 5)

            if model.visibleSessions.isEmpty {
                Text(model.staleCount > 0 ? "Nothing needs you" : "No live sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.visibleSessions.enumerated()), id: \.element.id) { index, session in
                        SessionRowView(session: session, isHovered: model.hoveredIndex == index)
                    }
                }
            }

            if model.staleCount > 0 {
                HStack(spacing: 7) {
                    MascotView(face: .idle, cell: MascotView.small)
                    Text("\(model.staleCount) idle")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            Color.clear.frame(height: 6)
        }
        .transition(.opacity)
    }

    /// The cutout row: the camera lives in the middle, so the name goes left of
    /// it and the count right of it.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                MascotView(face: model.face)
                Text("Roost")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchSize.width)

            headline
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: notchSize.height)
    }

    /// One line for the whole fleet, loudest fact first.
    @ViewBuilder
    private var headline: some View {
        if model.blockedCount > 0 {
            Text("\(model.blockedCount) waiting").foregroundStyle(model.face.colour.swiftUI)
        } else if model.runningCount > 0 {
            Text("\(model.runningCount) running").foregroundStyle(MascotFace.running.colour.swiftUI)
        } else {
            Text("\(model.visibleSessions.count) session\(model.visibleSessions.count == 1 ? "" : "s")")
                .foregroundStyle(Brand.textTertiary)
        }
    }
}
