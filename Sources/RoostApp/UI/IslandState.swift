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
    /// Which answer of a held question the cursor is on.
    var hoveredOption: Int?
    var hoveredMenu = false
    /// Whether the cursor is on the quota meters, which spells their reset
    /// times out along the footer.
    var hoveredUsage = false

    /// A held tool call opens every island: it is addressed to the person, not
    /// to a display, and they may be looking at either one.
    func showsPanel(pinned: Bool) -> Bool { isExpanded || pinned }
}
