import SwiftUI
import RoostCore

/// The island: collapsed it is the signal, expanded it is the session list.
///
/// Design rule this file enforces: growth belongs to `.blocked` alone. The
/// mascot has a pulse of its own in every state -- see `PixelChick.clip` -- but
/// all of it happens inside the same box, so a change of *shape* at the notch
/// still carries exactly one meaning and never has to be interpreted.
struct IslandView: View {
    @Bindable var model: RoostModel
    /// This screen's own hover state.
    @Bindable var state: IslandState
    /// Physical cutout size: the island's resting shape and the camera gap.
    let notchSize: CGSize

    private var showsPanel: Bool { state.showsPanel(pinned: model.isPinned) }

    private var strings: Strings { model.strings }

    private var size: CGSize {
        IslandGeometry.size(level: model.level,
                            tier: model.tier,
                            notch: notchSize,
                            expanded: showsPanel,
                            sessionCount: model.visibleSessions.count,
                            hasFooter: model.hasFooter,
                            heldHeight: model.heldHeight)
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
        if model.level == .dormant && !showsPanel {
            Color.clear.frame(width: notchSize.width, height: notchSize.height)
        } else {
            ZStack {
                IslandShape(bottomRadius: IslandGeometry.bottomRadius(level: model.level,
                                                                     expanded: showsPanel))
                    .fill(.black)
                    .shadow(color: .black.opacity(0.55), radius: 8, y: 3)


                if showsPanel {
                    expandedContent
                } else {
                    CollapsedContent(face: model.face,
                                     level: model.level,
                                     sessionCount: model.visibleSessions.count,
                                     blockedCount: model.blockedCount,
                                     countdown: countdown,
                                     notchWidth: notchSize.width)
                }
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.24, dampingFraction: 0.74), value: state.isExpanded)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.level)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.tier)
        }
    }

    /// The conversation a held call belongs to. The card names it rather than
    /// leaving it to the row underneath: the card is the thing being answered.
    private func heldTitle(_ held: ApprovalRequest) -> String? {
        model.sessions.first { $0.id == held.sessionId }?.name
    }

    /// What the collapsed island says instead of a count while a window is
    /// spent: how long until it comes back, which is the only thing left to do
    /// something about.
    private var countdown: String? {
        guard model.face == .spent, let remaining = model.spentUsage?.remaining()
        else { return nil }
        return strings.elapsed(Int(remaining))
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

            if let held = model.approvals.current {
                switch held.kind {
                case .permission:
                    ApprovalCard(request: held, title: heldTitle(held),
                                 hovered: state.hoveredApproval, strings: strings)
                case .question(let question):
                    QuestionCard(request: held, question: question, title: heldTitle(held),
                                 hoveredOption: state.hoveredOption, strings: strings)
                case .plan(let plan):
                    PlanCard(request: held, plan: plan, title: heldTitle(held),
                             hovered: state.hoveredApproval, strings: strings)
                }
            }

            if model.visibleSessions.isEmpty {
                Text(model.staleCount > 0 ? strings.nothingNeedsYou : strings.noLiveSessions)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.visibleSessions.enumerated()), id: \.element.id) { index, session in
                        SessionRowView(session: session,
                                       isHovered: state.hoveredIndex == index,
                                       strings: strings)
                    }
                }
            }

            if model.hasFooter { footer }
            Color.clear.frame(height: 6)
        }
        .transition(.opacity)
    }

    /// Everything true of the fleet rather than of any one session. The meters
    /// sit flush right so their hover target is a fixed rectangle, and the
    /// whole strip gives way to the reset times while the cursor is on them.
    private var footer: some View {
        HStack(spacing: 9) {
            if state.hoveredUsage, let usage = model.liveUsage {
                UsageDetail(usage: usage, strings: strings)
            } else {
                if model.staleCount > 0 {
                    MascotView(face: .idle, cell: MascotView.small)
                    Text(strings.idleCount(model.staleCount))
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textTertiary)
                }
                Spacer(minLength: 6)
                if let update = model.update {
                    Text(strings.updateAvailable(update.version))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MascotFace.done.colour.swiftUI)
                }
                if let usage = model.liveUsage {
                    UsageMeters(usage: usage, strings: strings)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IslandGeometry.Footer.inset)
        .padding(.top, 4)
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

            HStack(spacing: 8) {
                headline.font(.system(size: 11, weight: .semibold, design: .rounded))
                menuButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: notchSize.height)
    }

    /// The way into settings, and with it the only visible way out of the app.
    /// A dot on it when there is a newer build.
    private var menuButton: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(state.hoveredMenu ? Brand.textPrimary : Brand.textSecondary)
            // The one control on the island, and a gear that turns under the
            // cursor is the cheapest way to say it is one.
            .rotationEffect(.degrees(state.hoveredMenu ? 60 : 0))
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: state.hoveredMenu)
            .frame(width: IslandGeometry.Menu.buttonSize,
                   height: IslandGeometry.Menu.buttonSize)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(state.hoveredMenu ? 0.14 : 0.06))
            )
            .overlay(alignment: .topTrailing) {
                if model.update != nil {
                    Circle()
                        .fill(MascotFace.done.colour.swiftUI)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: -2)
                }
            }
    }

    /// One line for the whole fleet, loudest fact first.
    ///
    /// A window about to run out sits above the count of what is running,
    /// because it is what will stop all of it. It says when the window comes
    /// back rather than how much has gone: past this point that is the only
    /// half of the figure anybody can act on.
    @ViewBuilder
    private var headline: some View {
        if model.blockedCount > 0 {
            Text(strings.waitingCount(model.blockedCount)).foregroundStyle(model.face.colour.swiftUI)
        } else if let tight = model.tightUsage {
            Text(tightWindow(tight))
                .foregroundStyle(Brand.usage(tight.window.used).swiftUI)
                .monospacedDigit()
        } else if model.runningCount > 0 {
            Text(strings.runningCount(model.runningCount)).foregroundStyle(MascotFace.running.colour.swiftUI)
        } else {
            Text(strings.sessionCount(model.visibleSessions.count))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    private func tightWindow(_ tight: (label: Usage.WindowLabel, window: UsageWindow)) -> String {
        let name = strings.name(of: tight.label)
        guard let remaining = tight.window.remaining() else {
            return "\(name) \(strings.percent(tight.window.used))"
        }
        return "\(name) · \(strings.resetsIn(Int(remaining)))"
    }
}
