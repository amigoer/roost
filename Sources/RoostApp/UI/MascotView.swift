import SwiftUI

/// The mascot slot.
///
/// Motion stays inside the pixel grid the way pixel art does -- whole cells,
/// held frames, nothing interpolated -- so the chick is as crisp mid-hop as it
/// is standing still. What each face does is written beside its art in
/// `PixelChick.clip`.
struct MascotView: View {
    let face: MascotFace
    /// Points per art cell. Whole or half points only: anything else lands
    /// between device pixels and the grid stops being crisp.
    var cell: CGFloat = MascotView.large

    /// Session rows.
    static let small: CGFloat = 1
    /// The collapsed island, the expanded header and the menu bar.
    static let large: CGFloat = 1.5

    var body: some View {
        PixelSprite(key: face,
                    clip: PixelChick.clip(face),
                    inks: face.inks,
                    cell: cell,
                    rows: PixelChick.rows)
            .frame(width: CGFloat(PixelChick.columns) * cell,
                   height: CGFloat(PixelChick.rows + PixelChick.hopRoom) * cell)
    }
}
