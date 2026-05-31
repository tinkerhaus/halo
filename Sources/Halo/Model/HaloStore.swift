import Foundation
import Observation
import Yams

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
        self.fileURL = base.appendingPathComponent("config.yaml")
        self.config = HaloStore.load(from: fileURL) ?? .starter()
        if config.summonButton < 2 { config.summonButton = 4 }   // left/right are never valid summon buttons
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
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(HaloConfig.self, from: yaml)
    }

    /// A self-documenting header re-emitted on every save (YAML `#` comments).
    /// Keeps the file explained in-place; survives round-trips because we
    /// regenerate it (your own comments are dropped when the app rewrites).
    private static let header = """
    # Halo configuration — this whole file controls the app.
    # Edits apply on the next summon (the file is watched live).
    #
    # summonButton : mouse button that opens the wheel (NSEvent number; 2=middle, 3=back, 4=forward).
    #                Left/right (0/1) are not allowed.
    # voice.finish : the default finish ring (a halo) shown when you stop a dictation.
    #                A profile may set its own `finish`; omit both for a built-in plain-Send ring.
    # voice.muteWhileRecording       : mute system output while recording (default false).
    # voice.pauseMediaWhileRecording : pause the Now-Playing app while recording, resume after (default false).
    # fallback     : the wheel shown when no profile matches the frontmost app.
    # profiles     : list of { name, apps: [bundleID], halo, finish? }. The frontmost app picks
    #                the profile; most specific (fewest apps) wins, so a 1-app profile overrides a group.
    # halo         : { arc: { spanDegrees, centerDegrees }, radius, spokes: [...], center? }
    #                The arc never closes a full circle; the empty wedge = release-to-cancel.
    #                centerDegrees -90 = straight up.
    # center       : steps fired when you release at the hub. Omit and it defaults by context —
    #                the action wheel dictates; a finish ring sends. e.g. center: [ {do: send}, {key: return} ]
    # spoke        : { label, glyph, <exactly one of>: key | text | steps | well }
    #                key   : a chord string, e.g. "cmd+shift+z", "ctrl+c", "tab", "cmd+[", "up"
    #                        mods: cmd|ctrl|opt|shift   keys: a-z 0-9, return/enter, esc, tab, space,
    #                        delete, up/down/left/right, home/end, and [ ] / \\\\ ; ' , . - = `
    #                text  : type literal text
    #                steps : ordered list of { key | text | paste | pause | do } — runs in sequence.
    #                        paste: N (clipboard history)   pause: ms
    #                        do: send | dictate | cancel | undo  (dictation verbs — see below)
    #                well  : a nested halo (a sub-ring you dwell into): { arc, radius, spokes }
    #                glyph : an SF Symbol name, e.g. "arrow.up", "stop.circle"
    # do (verbs)   : dictate — start a voice session (the hub becomes the live waveform)
    #                send    — inject what you just dictated (compose with keys, e.g. [ {do: send}, {key: return} ])
    #                cancel  — discard the recording without injecting
    #                undo    — delete the last dictation you injected (works even where ⌘Z doesn't)

    """

    private func save() {
        let snapshot = config
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.write(snapshot) }
    }

    private func write(_ config: HaloConfig) {
        guard let yaml = try? YAMLEncoder().encode(config) else { return }
        let out = HaloStore.header + yaml
        try? out.data(using: .utf8)?.write(to: fileURL, options: .atomic)
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
