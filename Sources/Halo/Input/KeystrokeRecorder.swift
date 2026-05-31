import AppKit
import Observation

/// Captures the next keystroke (key + modifiers) the user presses while Halo's
/// window is focused — for recording a spoke's `key` step in the editor. Mirrors
/// `ButtonRecorder`. Uses a *local* event monitor, so it only intercepts keys in
/// Halo's own window and swallows the captured event (it won't leak into a field).
@Observable
final class KeystrokeRecorder {
    private(set) var isRecording = false
    private var monitor: Any?

    /// Start listening. The completion fires once, on the main thread, with the
    /// captured key code + modifiers; recording then stops. Any key is accepted
    /// (including Esc), so every spoke key is assignable — cancel via `stop()`.
    func record(_ completion: @escaping (UInt16, Modifiers) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            let mods = KeystrokeRecorder.modifiers(from: event.modifierFlags)
            self.stop()
            completion(event.keyCode, mods)
            return nil   // swallow — don't type the captured key into the app
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift)   { m.insert(.shift) }
        if flags.contains(.option)  { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }
}
