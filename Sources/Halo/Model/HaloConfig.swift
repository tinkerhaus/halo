import Foundation

/// macOS virtual key codes, named for readability where we use them.
enum Key {
    static let enter: UInt16 = 36, esc: UInt16 = 53, tab: UInt16 = 48, delete: UInt16 = 51
    static let up: UInt16 = 126, down: UInt16 = 125, left: UInt16 = 123, right: UInt16 = 124
    static let c: UInt16 = 8, d: UInt16 = 2, r: UInt16 = 15, u: UInt16 = 32, l: UInt16 = 37
    static let s: UInt16 = 1, z: UInt16 = 6, f: UInt16 = 3, t: UInt16 = 17, w: UInt16 = 13
    static let slash: UInt16 = 44, leftBracket: UInt16 = 33, rightBracket: UInt16 = 30
}

/// Voice / dictation options. `finish` is the global default finish ring (shown
/// when you stop a hands-free session); a profile may override it, and if both
/// are omitted a built-in plain-Send ring is used.
struct VoiceConfig: Codable, Equatable {
    var finish: Halo?

    init(finish: Halo? = nil) { self.finish = finish }

    enum CodingKeys: String, CodingKey { case finish }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finish = try? c.decodeIfPresent(Halo.self, forKey: .finish)
    }
}

/// A runtime condition that makes a profile match only when it holds — so the same
/// app can map to different wheels depending on what's actually running. `process`
/// is true when a process of that name is the frontmost app or a descendant of it
/// (e.g. `claude` running inside the front terminal). `titleMatches` is a regex
/// against the focused window's title. Both given ⇒ both must hold. Evaluated
/// natively (no shell) so it's cheap on summon.
struct WhenMatch: Codable, Equatable {
    var process: String?
    var titleMatches: String?

    var isEmpty: Bool { (process ?? "").isEmpty && (titleMatches ?? "").isEmpty }

    init(process: String? = nil, titleMatches: String? = nil) {
        self.process = process; self.titleMatches = titleMatches
    }

    private enum K: String, CodingKey { case process, titleMatches }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        if let process, !process.isEmpty { try c.encode(process, forKey: .process) }
        if let titleMatches, !titleMatches.isEmpty { try c.encode(titleMatches, forKey: .titleMatches) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        process = (try? c.decode(String.self, forKey: .process)).flatMap { $0.isEmpty ? nil : $0 }
        titleMatches = (try? c.decode(String.self, forKey: .titleMatches)).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A halo bound to a set of apps. The frontmost app picks the profile; if none
/// match, the config's `default` halo is used. An optional `when` narrows the match
/// to a runtime condition (e.g. Claude Code running in the front terminal), and a
/// matching `when`-profile beats a plain one. Serializes as `{name, apps, halo, …}`
/// (the `id` is runtime-only).
struct Profile: Equatable, Identifiable {
    var id = UUID()
    var name: String
    var appBundleIDs: [String]
    var halo: Halo
    var finish: Halo?            // optional per-app finish ring (overrides voice.finish)
    var context: ContextConfig?  // optional per-app context source for {context} (overrides the global one)
    var when: WhenMatch?         // optional runtime condition; a matching `when`-profile wins over a plain one

    init(name: String, appBundleIDs: [String], halo: Halo, finish: Halo? = nil,
         context: ContextConfig? = nil, when: WhenMatch? = nil) {
        self.name = name
        self.appBundleIDs = appBundleIDs
        self.halo = halo
        self.finish = finish
        self.context = context
        self.when = when
    }

    // `id` is runtime-only — exclude it from equality (see Spoke).
    static func == (a: Profile, b: Profile) -> Bool {
        a.name == b.name && a.appBundleIDs == b.appBundleIDs && a.halo == b.halo
            && a.finish == b.finish && a.context == b.context && a.when == b.when
    }
}

extension Profile: Codable {
    private enum K: String, CodingKey { case name, apps, halo, finish, context, when }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(name, forKey: .name)
        try c.encode(appBundleIDs, forKey: .apps)
        try c.encode(halo, forKey: .halo)
        try c.encodeIfPresent(finish, forKey: .finish)
        try c.encodeIfPresent(context, forKey: .context)
        try c.encodeIfPresent(when, forKey: .when)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        appBundleIDs = (try? c.decodeIfPresent([String].self, forKey: .apps)) ?? []
        halo = (try? c.decodeIfPresent(Halo.self, forKey: .halo)) ?? Halo()
        finish = try? c.decodeIfPresent(Halo.self, forKey: .finish)
        context = try? c.decodeIfPresent(ContextConfig.self, forKey: .context)
        when = try? c.decodeIfPresent(WhenMatch.self, forKey: .when)
    }
}

/// The single source of truth for everything Halo does — summon button, the
/// default wheel, and per-app profiles. This is the whole `halo.json`.
///
/// Decoding is lenient: omit any field and it falls back to a sensible default,
/// so the JSON is comfortable to hand-edit.
struct HaloConfig: Codable, Equatable {
    var summonButton: Int
    var sounds: Bool               // soft UI cues on summon / select / fire / send
    var voice: VoiceConfig
    var llm: LLMConfig?            // OpenAI-compatible endpoints (the engines) functions run on
    var functions: [String: Function]? // named functions a spoke calls by name (each has a prompt + variables)
    var context: ContextConfig?   // global default {context} source (a profile may override per-app)
    var defaultHalo: Halo          // wheel shown when no profile matches (YAML key: `default`)
    var profiles: [Profile]

    init(summonButton: Int = 4, sounds: Bool = true, voice: VoiceConfig = VoiceConfig(),
         llm: LLMConfig? = nil, functions: [String: Function]? = nil, context: ContextConfig? = nil,
         defaultHalo: Halo, profiles: [Profile]) {
        self.summonButton = summonButton
        self.sounds = sounds
        self.voice = voice
        self.llm = llm
        self.functions = functions
        self.context = context
        self.defaultHalo = defaultHalo
        self.profiles = profiles
    }

    // `default` is the user-facing key; `fallback` is still read as a deprecated
    // alias so existing configs load (they self-heal to `default` on the next save).
    enum CodingKeys: String, CodingKey { case summonButton, sounds, voice, llm, functions, context, profiles, defaultHalo = "default" }
    private enum LegacyKeys: String, CodingKey { case fallback }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = HaloConfig.starter()
        summonButton = (try? c.decodeIfPresent(Int.self, forKey: .summonButton)) ?? base.summonButton
        sounds = (try? c.decodeIfPresent(Bool.self, forKey: .sounds)) ?? base.sounds
        voice = (try? c.decodeIfPresent(VoiceConfig.self, forKey: .voice)) ?? base.voice
        llm = (try? c.decodeIfPresent(LLMConfig.self, forKey: .llm)) ?? nil
        functions = (try? c.decodeIfPresent([String: Function].self, forKey: .functions)) ?? nil
        context = (try? c.decodeIfPresent(ContextConfig.self, forKey: .context)) ?? nil
        var resolved = (try? c.decodeIfPresent(Halo.self, forKey: .defaultHalo)) ?? nil
        if resolved == nil, let legacy = try? decoder.container(keyedBy: LegacyKeys.self) {
            resolved = (try? legacy.decodeIfPresent(Halo.self, forKey: .fallback)) ?? nil
        }
        defaultHalo = resolved ?? base.defaultHalo
        profiles = (try? c.decodeIfPresent([Profile].self, forKey: .profiles)) ?? base.profiles
    }

    /// The profile matching a frontmost app — most specific (fewest apps) wins,
    /// so a single-app profile overrides a group it also belongs to.
    private func profile(forApp bundleID: String?) -> Profile? {
        guard let bundleID else { return nil }
        return profiles
            .filter { $0.appBundleIDs.contains(bundleID) && $0.when == nil }   // static profiles only
            .min { $0.appBundleIDs.count < $1.appBundleIDs.count }
    }

    /// The active profile for the frontmost app, honoring `when` conditions: a
    /// `when`-profile whose condition currently holds (evaluated by `matches`) wins
    /// over any plain profile; otherwise the most-specific plain profile. Used for
    /// the live wheel so the layout can follow what's running (e.g. Claude Code).
    func activeProfile(forApp bundleID: String?, matches: (WhenMatch) -> Bool) -> Profile? {
        guard let bundleID else { return nil }
        let candidates = profiles.filter { $0.appBundleIDs.contains(bundleID) }
        if let dynamic = candidates
            .filter({ ($0.when.map { !$0.isEmpty } ?? false) && matches($0.when!) })
            .min(by: { $0.appBundleIDs.count < $1.appBundleIDs.count }) {
            return dynamic
        }
        return candidates.filter { $0.when == nil }.min { $0.appBundleIDs.count < $1.appBundleIDs.count }
    }

    /// The halo to summon for a given frontmost app.
    func halo(forApp bundleID: String?) -> Halo {
        profile(forApp: bundleID)?.halo ?? defaultHalo
    }

    /// The finish ring for a given frontmost app: the matched profile's, else the
    /// global `voice.finish`, else the built-in plain-Send default.
    func finish(forApp bundleID: String?) -> Halo {
        profile(forApp: bundleID)?.finish ?? voice.finish ?? HaloConfig.defaultFinish()
    }

    /// How to capture `{context}` for a given frontmost app: the matched profile's
    /// source, else the global one, else the built-in AX default (lines before caret).
    func contextConfig(forApp bundleID: String?) -> ContextConfig {
        profile(forApp: bundleID)?.context ?? context ?? .defaultAX
    }

    // MARK: - Starter configuration

    private static func arc(_ span: Int) -> Arc { Arc(spanDegrees: span, centerDegrees: -90) }

    /// Inject the transcript, optionally pressing Return after.
    private static func send(enter: Bool = false) -> Action {
        Action(enter ? [.verb(.send), .key(code: Key.enter, modifiers: [])] : [.verb(.send)])
    }

    /// Built-in finish ring when none is configured: release-at-center sends the
    /// text as-is (safe — no surprise Return), with Submit (+Return) and Cancel
    /// one flick away.
    static func defaultFinish() -> Halo {
        Halo(arc: arc(200), radius: 108, spokes: [
            .action("Submit", "return", send(enter: true)),
            .action("Cancel", "xmark", Action([.verb(.cancel)])),
        ], center: send())
    }

    /// Finish ring for chat-like apps: release-at-center submits (Send+Return),
    /// with a Send-only and Cancel flick.
    private static func submitFinish() -> Halo {
        Halo(arc: arc(200), radius: 108, spokes: [
            .action("Send only", "arrow.up", send()),
            .action("Cancel", "xmark", Action([.verb(.cancel)])),
        ], center: send(enter: true))
    }

    static func starter() -> HaloConfig {
        HaloConfig(summonButton: 4, voice: VoiceConfig(finish: defaultFinish()), defaultHalo: makeDefaultHalo(),
                   profiles: [terminalProfile(), browserProfile(), editorProfile()])
    }

    private static func makeDefaultHalo() -> Halo {
        Halo(arc: arc(200), spokes: [
            .action("Enter", "return", .key(Key.enter)),
            .action("Up", "arrow.up", .key(Key.up)),
            .action("Down", "arrow.down", .key(Key.down)),
            .action("Esc", "escape", .key(Key.esc)),
            .action("Delete", "delete.left", .key(Key.delete)),
            .well("Nav", "arrow.up.and.down.and.arrow.left.and.right",
                  Halo(arc: arc(180), spokes: [
                    .action("Left", "arrow.left", .key(Key.left)),
                    .action("Right", "arrow.right", .key(Key.right)),
                  ])),
        ])
    }

    private static func terminalProfile() -> Profile {
        Profile(name: "Terminal / Agent",
                appBundleIDs: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                               "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty",
                               "com.github.wez.wezterm"],
                halo: Halo(arc: arc(210), spokes: [
                    .action("Enter", "return", .key(Key.enter)),
                    .action("Up", "arrow.up", .key(Key.up)),
                    .action("Down", "arrow.down", .key(Key.down)),
                    .action("Tab", "arrow.right.to.line", .key(Key.tab)),
                    .action("Esc", "escape", .key(Key.esc)),
                    .action("Stop", "stop.circle", .key(Key.c, .control)),
                    .well("More", "ellipsis.circle", Halo(arc: arc(180), spokes: [
                        .action("⇧Tab", "arrow.left.to.line", .key(Key.tab, .shift)),
                        .action("Search", "magnifyingglass", .key(Key.r, .control)),
                        .action("Clear", "delete.left", .key(Key.u, .control)),
                        .action("Undo voice", "arrow.uturn.backward", Action([.verb(.undo)])),
                        .action("EOF", "eject", .key(Key.d, .control)),
                        .action("Cls", "rectangle.dashed", .key(Key.l, .control)),
                    ])),
                ]),
                finish: submitFinish())
    }

    private static func browserProfile() -> Profile {
        Profile(name: "Browser",
                appBundleIDs: ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                               "com.brave.Browser", "org.mozilla.firefox", "com.microsoft.edgemac"],
                halo: Halo(arc: arc(210), spokes: [
                    .action("Back", "chevron.left", .key(Key.leftBracket, .command)),
                    .action("Forward", "chevron.right", .key(Key.rightBracket, .command)),
                    .action("Reload", "arrow.clockwise", .key(Key.r, .command)),
                    .action("New Tab", "plus.square", .key(Key.t, .command)),
                    .action("Close", "xmark.square", .key(Key.w, .command)),
                    .action("Find", "magnifyingglass", .key(Key.f, .command)),
                    .well("Tabs", "ellipsis.circle", Halo(arc: arc(160), spokes: [
                        .action("Address", "link", .key(Key.l, .command)),
                        .action("Next Tab", "chevron.right.2", .key(Key.tab, .control)),
                        .action("Prev Tab", "chevron.left.2", .key(Key.tab, [.control, .shift])),
                        .action("Undo voice", "arrow.uturn.backward", Action([.verb(.undo)])),
                    ])),
                ]),
                finish: submitFinish())
    }

    private static func editorProfile() -> Profile {
        Profile(name: "Editor / IDE",
                appBundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                               "com.apple.dt.Xcode", "dev.zed.Zed"],
                halo: Halo(arc: arc(210), spokes: [
                    .action("Save", "square.and.arrow.down", .key(Key.s, .command)),
                    .action("Undo", "arrow.uturn.backward", .key(Key.z, .command)),
                    .action("Redo", "arrow.uturn.forward", .key(Key.z, [.command, .shift])),
                    .action("Find", "magnifyingglass", .key(Key.f, .command)),
                    .action("Comment", "text.bubble", .key(Key.slash, .command)),
                    .well("Nav", "ellipsis.circle", Halo(arc: arc(180), spokes: [
                        .action("Up", "arrow.up", .key(Key.up)),
                        .action("Down", "arrow.down", .key(Key.down)),
                        .action("Left", "arrow.left", .key(Key.left)),
                        .action("Right", "arrow.right", .key(Key.right)),
                    ])),
                ]))
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
