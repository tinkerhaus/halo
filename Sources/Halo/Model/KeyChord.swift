import Foundation

/// Parses and formats keystroke chords as readable strings — `"cmd+shift+z"`,
/// `"ctrl+c"`, `"shift+tab"`, `"return"`, `"cmd+["` — so the config JSON stays
/// human-editable instead of raw virtual key codes + bitmasks.
enum KeyChord {
    /// Named keys → virtual key code. The first name listed is the canonical one
    /// used when formatting back to a string.
    private static let names: [(String, UInt16)] = [
        ("return", 36), ("enter", 36), ("tab", 48), ("esc", 53), ("escape", 53),
        ("space", 49), ("delete", 51), ("backspace", 51), ("fwddelete", 117),
        ("up", 126), ("down", 125), ("left", 123), ("right", 124),
        ("home", 115), ("end", 119), ("pageup", 116), ("pagedown", 121),
        ("[", 33), ("]", 30), ("/", 44), ("\\", 42), (";", 41), ("'", 39),
        (",", 43), (".", 47), ("-", 27), ("=", 24), ("`", 50),
    ]
    private static let letters: [(String, UInt16)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
        ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
        ("y", 16), ("t", 17), ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37),
        ("j", 38), ("k", 40), ("n", 45), ("m", 46),
    ]
    private static let digits: [(String, UInt16)] = [
        ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21),
        ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25),
    ]

    private static let codeForName: [String: UInt16] =
        Dictionary(names + letters + digits, uniquingKeysWith: { a, _ in a })
    private static let nameForCode: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for (name, code) in (names + letters + digits) where map[code] == nil { map[code] = name }
        return map
    }()

    /// Parse a chord string into a key code + modifiers. Last token is the key.
    static func parse(_ string: String) -> (code: UInt16, modifiers: Modifiers)? {
        let tokens = string.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let keyToken = tokens.last else { return nil }
        var modifiers: Modifiers = []
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "shift", "⇧":          modifiers.insert(.shift)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            default: return nil
            }
        }
        guard let code = code(for: keyToken) else { return nil }
        return (code, modifiers)
    }

    /// Format a key code + modifiers as a canonical chord string.
    static func format(code: UInt16, modifiers: Modifiers) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("opt") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(nameForCode[code] ?? "key\(code)")
        return parts.joined(separator: "+")
    }

    private static func code(for token: String) -> UInt16? {
        if let code = codeForName[token] { return code }
        if token.hasPrefix("key"), let n = UInt16(token.dropFirst(3)) { return n }   // raw fallback
        return nil
    }
}
