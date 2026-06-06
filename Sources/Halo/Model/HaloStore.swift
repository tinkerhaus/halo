import Foundation
import Observation
import Yams

/// The single source of truth for Halo, backed by `halo.json`. Everything —
/// summon button, default wheel, per-app profiles — lives in this one file.
/// It's watched on disk, so hand/AI edits apply live with no restart.
@Observable
final class HaloStore {
    private let fileURL: URL
    var config: HaloConfig { didSet { save() } }

    /// The Wheels editor's working copy. Edits mutate this with **no** disk write;
    /// `commitDraft()` is the explicit Save. Held on the store (not the editor view)
    /// so unsaved edits survive the window closing or the pane being switched away.
    var draft: HaloConfig
    var hasUnsavedChanges: Bool { draft != config }

    /// A manually-pinned profile name (from the menu bar) that overrides automatic
    /// app/`when` matching; nil = automatic. Runtime-only — resets to automatic on
    /// relaunch, and never written to disk (so it can't race the config reload).
    var profileOverride: String?

    var configURL: URL { fileURL }

    /// Non-nil when the on-disk config failed to parse. Halo falls back to the
    /// last-good config (or defaults) and surfaces this in the menu & Settings.
    private(set) var configError: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var saveWork: DispatchWorkItem?

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Halo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("config.yaml")

        // Load, capturing a parse error so we can surface it instead of silently
        // falling back. A broken file is left on disk (never overwritten) so it can be fixed.
        var loaded: HaloConfig
        var error: String?
        do {
            loaded = try HaloStore.parse(from: url) ?? .starter()
        } catch let e {
            loaded = .starter()
            error = HaloStore.message(for: e)
        }
        if loaded.summonButton < 2 { loaded.summonButton = 4 }   // left/right are never valid summon buttons

        self.fileURL = url
        self.config = loaded
        self.draft = loaded
        self.configError = error
        if !FileManager.default.fileExists(atPath: url.path) { write(loaded) }   // seed the file
        startWatching()
    }

    // Convenience accessors.
    var summonButton: Int {
        get { config.summonButton }
        set { config.summonButton = newValue }
    }
    func halo(forApp bundleID: String?) -> Halo { config.halo(forApp: bundleID) }

    /// Overwrite the on-disk config with the built-in defaults.
    func resetToStarter() {
        configError = nil
        config = .starter()      // didSet → save() rewrites config.yaml with clean defaults
        draft = config
    }

    /// Commit the editor's working copy to disk (the explicit Save).
    func commitDraft() { config = draft }   // didSet → save()

    /// Throw away unsaved editor changes, reverting to what's on disk.
    func discardDraft() { draft = config }

    /// Re-read from disk if it changed underneath us. No-ops when identical, so
    /// our own saves don't cause a loop. Surfaces a parse error rather than
    /// silently discarding the user's (broken) edits — the last good config stays live.
    func reload() {
        do {
            guard let fresh = try HaloStore.parse(from: fileURL) else { return }
            configError = nil
            if fresh != config {
                let draftWasClean = (draft == config)
                config = fresh
                if draftWasClean { draft = fresh }   // keep an unedited draft in sync with the file
            }
        } catch {
            configError = HaloStore.message(for: error)
        }
    }

    // MARK: - Disk

    /// Decode the config from disk. Returns nil if the file is missing/unreadable;
    /// throws if it's present but malformed (e.g. a YAML syntax error).
    private static func parse(from url: URL) throws -> HaloConfig? {
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try YAMLDecoder().decode(HaloConfig.self, from: yaml)
    }

    /// A short, single-line description of a config parse failure.
    private static func message(for error: Error) -> String {
        var text = "\(error)".replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if text.count > 180 { text = String(text.prefix(180)) + "…" }
        return text
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
    # sounds       : soft UI cues on summon / select / fire / send (true or false).
    # voice.finish : the default finish ring (a halo) shown when you stop a dictation.
    #                A profile may set its own `finish`; omit both for a built-in plain-Send ring.
    # llm          : OpenAI-compatible endpoints (the *engines*) — optional, omit if unused.
    #                  providers: { <name>: { base: "<url ending in /v1>", model, keyRef?, thinking? } }
    #                  default:   which provider a function uses when it names none
    #                thinking: false ⇒ tell the server to disable the model's reasoning (faster; sends
    #                          chat_template_kwargs.enable_thinking=false). Omit to leave the model's default.
    #                keyRef is a *Keychain* item name (NOT the key) — service "Halo". Add a key with:
    #                  security add-generic-password -s Halo -a <keyRef> -w <your-api-key>
    #                Local servers (vLLM/Ollama) usually need no key — omit keyRef. e.g.:
    #                  llm:
    #                    providers:
    #                      local:  { base: "http://localhost:11434/v1", model: "llama3.1" }
    #                      openai: { base: "https://api.openai.com/v1", model: "gpt-4o-mini", keyRef: "openai" }
    #                    default: local
    # functions    : named functions a spoke calls by name (the *what to do*) — optional. Each:
    #                { prompt, variables?, provider?, temperature? }. `prompt` interpolates {variables}:
    #                {transcript} (the dictation), the function's own variables (with defaults), and values
    #                passed at the call site. The dictation is the function's input. e.g.:
    #                  functions:
    #                    clean:     { prompt: "Clean up this dictation. Output only the cleaned text." }
    #                    translate: { prompt: "Translate to {lang}. Output only the translation.",
    #                                 variables: { lang: English } }
    #                    ask:       { prompt: "Answer the user concisely." }
    # context      : how to fill {context} when a function's prompt uses it (optional). Captured once,
    #                when dictation starts — it also biases the transcriber toward the surrounding text.
    #                  { lines: N }            read N lines before the caret via Accessibility (default 12;
    #                                          works in native text fields — TextEdit, Mail, Notes, …)
    #                  { bash: "command" }     use a command's stdout instead (e.g. terminal scrollback)
    #                Set globally here, and/or per-profile (a profile's `context` wins for its apps). e.g.:
    #                  context: { lines: 12 }
    #                  …and inside a terminal profile: context: { bash: "tmux capture-pane -p | tail -40" }
    # default      : the wheel shown when no profile matches the frontmost app.
    # profiles     : list of { name, apps: [bundleID], halo, finish?, context?, when? }. The frontmost app
    #                picks the profile; most specific (fewest apps) wins, so a 1-app profile overrides a group.
    #                when : a runtime condition — the profile only matches while it holds, and a matching
    #                       `when`-profile beats a plain one (so the same app → different wheels). Fields:
    #                         process: "name"      true if that process runs under the frontmost app
    #                                              (e.g. `claude` inside the front terminal)
    #                         titleMatches: "regex" true if the focused window title matches
    #                       Both given ⇒ both must hold. e.g. a Claude-Code wheel: when: { process: claude }
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
    #                steps : ordered list — runs in sequence. Each is one of { key | text | paste | pause |
    #                        do | bash } OR a function call (just the function's name).
    #                        paste: N (clipboard history)   pause: ms
    #                        do: send | dictate | cancel | undo  (dictation verbs — see below)
    #                        bash: "shell command" — runs via your login shell; $HALO_TRANSCRIPT holds the
    #                              dictation. `inject: true` types its stdout back. `as: name` saves the
    #                              stdout so a later step can read it as $name (steps run in order).
    #                        function call: the function's name (from `functions:`). Bare `- clean` calls it
    #                              and types the reply back. To pass variables / qualify, use the map form:
    #                              `- translate: { lang: French }` with optional `inject:` (default true),
    #                              `provider:`, and `as: name` (save the reply) as siblings. An unknown name
    #                              is used as a literal instruction. If no provider / the call fails, the
    #                              dictation is passed through untouched, so words are never lost.
    #                well  : a nested halo (a sub-ring you dwell into): { arc, radius, spokes }
    #                glyph : an SF Symbol name, e.g. "arrow.up", "stop.circle"
    # do (verbs)   : dictate — start a voice session (the hub becomes the live waveform)
    #                send    — inject what you just dictated (compose with keys, e.g. [ {do: send}, {key: return} ])
    #                cancel  — discard the recording without injecting
    #                undo    — delete the last dictation you injected (works even where ⌘Z doesn't)

    """

    /// Coalesce rapid edits (slider drags, typing in the editor) into one write
    /// ~0.3s after they settle, so a config change per keystroke doesn't thrash the
    /// file. The watcher's reload no-ops on our own writes (content is identical).
    private func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.config
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.write(snapshot) }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
