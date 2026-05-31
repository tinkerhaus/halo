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

/// One unit of work a spoke performs.
enum Step: Codable, Equatable {
    case key(code: UInt16, modifiers: Modifiers)   // a keystroke / chord
    case text(String)                              // type literal text
    case paste(recent: Int)                        // paste an entry from clipboard history (0 = latest)
    case pause(milliseconds: Int)                  // wait before the next step
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
