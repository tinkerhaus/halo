import Foundation
import Observation

/// Captures the next mouse button the user clicks — for choosing the summon
/// button in Settings. Uses `MouseHID` so it works even for driver-remapped
/// side buttons.
@Observable
final class ButtonRecorder {
    private(set) var isRecording = false
    private var token: UUID?

    func record(_ completion: @escaping (Int) -> Void) {
        guard !isRecording else { return }
        MouseHID.shared.start()
        isRecording = true
        token = MouseHID.shared.subscribe { [weak self] button, pressed in
            guard pressed, let self else { return }
            self.stop()
            completion(button)
        }
    }

    func stop() {
        if let token { MouseHID.shared.unsubscribe(token) }
        token = nil
        isRecording = false
    }
}
