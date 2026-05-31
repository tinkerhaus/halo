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
    /// Bumped whenever a new level is shown, so the view replays the bloom-in.
    var revealID = 0
    /// Bumped when the wheel is dismissed, so the view plays the collapse-out.
    var collapseID = 0
    /// Center hovered but the voice model isn't ready yet.
    var modelLoading = false
    /// A dictation session is active — the hub becomes the recording UI.
    var recording = false
    /// Transcription is running (session winding down).
    var transcribing = false
    /// This is the finish ring (post-recording): the center commits/sends.
    var finishing = false
    /// The transcript to preview before sending (empty until it's ready).
    var transcript = ""
    /// Recent mic levels (0…1) for the live waveform in the hub.
    var levels: [Float] = []
}
