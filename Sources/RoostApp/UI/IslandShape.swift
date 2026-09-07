import SwiftUI
import RoostCore

/// The island silhouette: square on top because it sits flush with the screen
/// edge, rounded below so drawn pixels and the physical cutout read as one shape.
struct IslandShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0,
                               bottomLeading: bottomRadius,
                               bottomTrailing: bottomRadius,
                               topTrailing: 0)
        ).path(in: rect)
    }

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
}
