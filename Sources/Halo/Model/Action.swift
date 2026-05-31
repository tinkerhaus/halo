import CoreGraphics

/// A keyboard modifier set — Halo's own type so the model stays free of
/// CoreGraphics and serializes as a clean bitmask.
struct Modifiers: OptionSet, Codable, Equatable {
    let rawValue: Int
    static let command = Modifiers(rawValue: 1 << 0)
    static let shift   = Modifiers(rawValue: 1 << 1)
    static let option  = Modifiers(rawValue: 1 << 2)
    static let control = Modifiers(rawValue: 1 << 3)

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift)   { flags.insert(.maskShift) }
        if contains(.option)  { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}

/// A dictation control verb — the one kind of step that only means anything
/// mid-dictation. Serializes as `{"do":"send"}`. Code provides this vocabulary;
/// config composes it into flows.
///   • dictate — start a voice session (the hub becomes the live recording UI)
///   • send    — inject the current transcript as text
///   • cancel  — discard the recording/session without injecting
///   • undo    — delete the last dictation we injected (app-independent)
enum Verb: String, Codable, Equatable, CaseIterable { case dictate, send, cancel, undo }

/// One unit of work a spoke performs. Serializes to a compact, readable form:
/// `{"key":"cmd+s"}`, `{"text":"…"}`, `{"paste":0}`, `{"pause":200}`, `{"do":"send"}`,
/// `{"bash":"agy -p \"$HALO_TRANSCRIPT\"", "inject":true}`.
enum Step: Codable, Equatable {
    case key(code: UInt16, modifiers: Modifiers)   // a keystroke / chord
    case text(String)                              // type literal text
    case paste(recent: Int)                        // paste an entry from clipboard history (0 = latest)
    case pause(milliseconds: Int)                  // wait before the next step
    case verb(Verb)                                // a dictation control verb (do: …)
    case bash(command: String, inject: Bool, name: String?)  // run a shell command; `name` saves its stdout as $name

    private enum K: String, CodingKey { case key, text, paste, pause, verb = "do", bash, inject, asName = "as" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case let .key(code, modifiers): try c.encode(KeyChord.format(code: code, modifiers: modifiers), forKey: .key)
        case let .text(text):           try c.encode(text, forKey: .text)
        case let .paste(recent):        try c.encode(recent, forKey: .paste)
        case let .pause(milliseconds):  try c.encode(milliseconds, forKey: .pause)
        case let .verb(verb):           try c.encode(verb.rawValue, forKey: .verb)
        case let .bash(command, inject, name):
            try c.encode(command, forKey: .bash)
            if inject { try c.encode(true, forKey: .inject) }   // omit the common `false`
            if let name, !name.isEmpty { try c.encode(name, forKey: .asName) }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        if let chord = try? c.decode(String.self, forKey: .key), let parsed = KeyChord.parse(chord) {
            self = .key(code: parsed.code, modifiers: parsed.modifiers)
        } else if let text = try? c.decode(String.self, forKey: .text) {
            self = .text(text)
        } else if let recent = try? c.decode(Int.self, forKey: .paste) {
            self = .paste(recent: recent)
        } else if let ms = try? c.decode(Int.self, forKey: .pause) {
            self = .pause(milliseconds: ms)
        } else if let raw = try? c.decode(String.self, forKey: .verb), let verb = Verb(rawValue: raw) {
            self = .verb(verb)
        } else if let command = try? c.decode(String.self, forKey: .bash) {
            let inject = (try? c.decode(Bool.self, forKey: .inject)) ?? false
            let name = (try? c.decode(String.self, forKey: .asName)).flatMap { $0.isEmpty ? nil : $0 }
            self = .bash(command: command, inject: inject, name: name)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Step needs one of: key, text, paste, pause, do, bash"))
        }
    }
}

/// What a spoke does when fired: an ordered list of steps. Define once, fire by
/// flick (gesture) — and, later, by voice trigger. This is Halo's one primitive.
struct Action: Codable, Equatable {
    var steps: [Step]

    init(_ steps: [Step]) { self.steps = steps }

    /// Convenience for the common single-keystroke spoke.
    static func key(_ code: UInt16, _ modifiers: Modifiers = []) -> Action {
        Action([.key(code: code, modifiers: modifiers)])
    }
}
