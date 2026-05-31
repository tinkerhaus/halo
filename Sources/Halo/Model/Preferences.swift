import Foundation
import Observation

/// App-level preferences (distinct from the wheel layout in `HaloStore`).
/// Persisted to `preferences.json`.
@Observable
final class Preferences {
    struct Stored: Codable {
        var summonButton: Int = 4          // NSEvent button number; 4 = forward side button
        var hoverSound: String = "Frog"
        var fireSound: String = "Frog"
    }

    private let fileURL: URL
    private var stored: Stored { didSet { save() } }

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Halo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("preferences.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            self.stored = decoded
        } else {
            self.stored = Stored()
        }
    }

    var summonButton: Int { get { stored.summonButton } set { stored.summonButton = newValue } }
    var hoverSound: String { get { stored.hoverSound } set { stored.hoverSound = newValue } }
    var fireSound: String { get { stored.fireSound } set { stored.fireSound = newValue } }

    private func save() {
        DispatchQueue.global(qos: .utility).async { [stored, fileURL] in
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(stored) { try? data.write(to: fileURL, options: .atomic) }
        }
    }
}

/// Human-readable name for an `NSEvent` mouse button number.
func mouseButtonName(_ n: Int) -> String {
    switch n {
    case 0: return "Left click"
    case 1: return "Right click"
    case 2: return "Middle click"
    case 3: return "Back (side button)"
    case 4: return "Forward (side button)"
    default: return "Button \(n + 1)"
    }
}
