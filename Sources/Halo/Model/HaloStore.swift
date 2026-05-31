import Foundation
import Observation

/// The single source of truth for Halo, backed by `halo.json`. Everything —
/// summon button, fallback wheel, per-app profiles — lives in this one file.
/// It's watched on disk, so hand/AI edits apply live with no restart.
@Observable
final class HaloStore {
    private let fileURL: URL
    var config: HaloConfig { didSet { save() } }

    var configURL: URL { fileURL }

    private var watcher: DispatchSourceFileSystemObject?

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Halo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("halo.json")
        self.config = HaloStore.load(from: fileURL) ?? .starter()
        if !FileManager.default.fileExists(atPath: fileURL.path) { write(config) }   // seed the file
        startWatching()
    }

    // Convenience accessors.
    var summonButton: Int {
        get { config.summonButton }
        set { config.summonButton = newValue }
    }
    func halo(forApp bundleID: String?) -> Halo { config.halo(forApp: bundleID) }
    func resetToStarter() { config = .starter() }

    /// Re-read from disk if it changed underneath us. No-ops when identical, so
    /// our own saves don't cause a loop.
    func reload() {
        guard let fresh = HaloStore.load(from: fileURL), fresh != config else { return }
        config = fresh
    }

    // MARK: - Disk

    private static func load(from url: URL) -> HaloConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HaloConfig.self, from: data)
    }

    private func save() {
        let snapshot = config
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.write(snapshot) }
    }

    private func write(_ config: HaloConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Watch `halo.json` and reload on external edits. Re-arms after each event
    /// since atomic writes replace the file's inode.
    private func startWatching() {
        watcher?.cancel()
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let self else { return }
                self.reload()
                self.startWatching()      // re-arm onto the new inode
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
