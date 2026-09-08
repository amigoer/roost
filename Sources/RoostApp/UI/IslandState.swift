import Observation
import RoostCore

/// What one screen's island is doing.
///
/// Separate from `RoostModel` because sessions are global and hover is not:
/// pointing at the island on one display must not open the one on another.
@MainActor
@Observable
final class IslandState {
    var isExpanded = false
    var hoveredIndex: Int?
    var hoveredApproval: IslandGeometry.ApprovalHit?

    /// A held tool call opens every island: it is addressed to the person, not
    /// to a display, and they may be looking at either one.
    func showsPanel(pinned: Bool) -> Bool { isExpanded || pinned }
}
