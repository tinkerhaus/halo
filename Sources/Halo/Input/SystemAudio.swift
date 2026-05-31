import AppKit
import CoreGraphics

/// Quiets other system audio while you dictate, then restores it. Two independent,
/// config-gated behaviors (see `VoiceConfig`):
///   • mute  — mute system output for the duration; restores the *prior* state, so
///             we never unmute audio you had muted yourself. Also keeps speaker
///             sound out of the mic, which helps transcription.
///   • pause — tap the Play/Pause media key to pause the Now-Playing app, and tap
///             again to resume. Nicer (the video actually stops) but it's a toggle:
///             if nothing was playing it may *start* something.
///
/// `quiet`/`restore` are idempotent and only undo what they did.
enum SystemAudio {
    private static var didMute = false
    private static var didPause = false

    static func quiet(mute: Bool, pauseMedia: Bool) {
        if mute, !didMute, !isOutputMuted() { setOutputMuted(true); didMute = true }
        if pauseMedia, !didPause { sendPlayPauseKey(); didPause = true }
    }

    static func restore() {
        if didMute { setOutputMuted(false); didMute = false }
        if didPause { sendPlayPauseKey(); didPause = false }
    }

    // MARK: Output mute — StandardAdditions volume (no Automation permission needed)

    private static func isOutputMuted() -> Bool {
        var error: NSDictionary?
        let r = NSAppleScript(source: "output muted of (get volume settings)")?.executeAndReturnError(&error)
        return r?.booleanValue ?? false
    }

    private static func setOutputMuted(_ muted: Bool) {
        var error: NSDictionary?
        _ = NSAppleScript(source: "set volume output muted \(muted)")?.executeAndReturnError(&error)
    }

    // MARK: Play/Pause media key (works system-wide; needs Accessibility, which we have)

    private static func sendPlayPauseKey() {
        let playKey = 16    // NX_KEYTYPE_PLAY
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (playKey << 16) | ((down ? 0xA : 0xB) << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                 modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                                 context: nil, subtype: 8, data1: data1, data2: -1)
            else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}
