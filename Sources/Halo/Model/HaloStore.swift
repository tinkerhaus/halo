import Foundation
import Observation

/// The source of truth for Halo's configuration. Persists to `halo.json` and is
/// re-read on demand, so the file can be hand-edited (by you or an AI) and the
/// next summon reflects it — no restart.
@Observable
final class HaloStore {
    private let fileURL: URL
    var configuration: Configuration { didSet { save() } }

    var configURL: URL { fileURL }

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Halo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("halo.json")
        self.configuration = HaloStore.load(from: fileURL) ?? .starter()
    }

    func halo(forApp bundleID: String?) -> Halo { configuration.halo(forApp: bundleID) }

    func resetToStarter() { configuration = .starter() }

    func reload() {
        guard let fresh = HaloStore.load(from: fileURL), fresh != configuration else { return }
        configuration = fresh
    }

    private static func load(from url: URL) -> Configuration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Configuration.self, from: data)
    }

    private func save() {
        DispatchQueue.global(qos: .utility).async { [configuration, fileURL] in
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(configuration) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
