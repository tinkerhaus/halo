import SwiftUI
import Observation

/// A spoke flattened for display — the view stays dumb; the controller resolves
/// the live `Halo` down to these.
struct WheelSpoke: Identifiable {
    let id: Int
    let label: String
    let glyph: String
    let isWell: Bool
}

/// Render state for the wheel. The controller updates `highlighted` from the
/// cursor each frame; the view is a pure function of this.
@Observable
final class WheelModel {
    var spokes: [WheelSpoke] = []
    var angles: [Angle] = []
    var radius: CGFloat = 124
    var highlighted: Int? = nil
    /// Cursor is in the empty wedge — releasing cancels.
    var inWedge = false
    /// Depth in the well stack (0 == root). Drives the center hint.
    var depth = 0
}
