import Foundation

/// One selectable item on a halo. A spoke either *performs* an action or *opens*
/// a nested halo (a "well" you dwell into).
///
/// Serializes compactly: `{label, glyph}` plus exactly one of `key` (a chord
/// string), `text`, `steps`, or `well` (a nested halo). The `id` is runtime-only
/// and never written to JSON.
struct Spoke: Equatable, Identifiable {
    var id = UUID()
    var label: String
    var glyph: String            // SF Symbol name
    var content: Content

    enum Content: Equatable {
        case performs(Action)
        case opens(Halo)
    }

    var isWell: Bool {
        if case .opens = content { return true }
        return false
    }

    static func action(_ label: String, _ glyph: String, _ action: Action) -> Spoke {
        Spoke(label: label, glyph: glyph, content: .performs(action))
    }
    static func well(_ label: String, _ glyph: String, _ halo: Halo) -> Spoke {
        Spoke(label: label, glyph: glyph, content: .opens(halo))
    }
}

extension Spoke: Codable {
    private enum K: String, CodingKey { case label, glyph, key, text, steps, well }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(label, forKey: .label)
        try c.encode(glyph, forKey: .glyph)
        switch content {
        case .opens(let halo):
            try c.encode(halo, forKey: .well)
        case .performs(let action):
            // Inline the common single-step shapes; fall back to the steps list.
            if action.steps.count == 1, case let .key(code, mods) = action.steps[0] {
                try c.encode(KeyChord.format(code: code, modifiers: mods), forKey: .key)
            } else if action.steps.count == 1, case let .text(text) = action.steps[0] {
                try c.encode(text, forKey: .text)
            } else {
                try c.encode(action.steps, forKey: .steps)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = UUID()
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        glyph = (try? c.decodeIfPresent(String.self, forKey: .glyph)) ?? "circle"
        if let well = try? c.decode(Halo.self, forKey: .well) {
            content = .opens(well)
        } else if let chord = try? c.decode(String.self, forKey: .key), let p = KeyChord.parse(chord) {
            content = .performs(Action([.key(code: p.code, modifiers: p.modifiers)]))
        } else if let steps = try? c.decode([Step].self, forKey: .steps) {
            content = .performs(Action(steps))
        } else if let text = try? c.decode(String.self, forKey: .text) {
            content = .performs(Action([.text(text)]))
        } else {
            content = .performs(Action([]))   // no-op placeholder
        }
    }
}

/// A ring of spokes: the arc they fan across, how far out they sit, and the
/// spokes themselves. Recursive — a spoke may open another `Halo`.
struct Halo: Codable, Equatable {
    var arc = Arc()
    var radius: Int = 124            // points from the hub to each spoke
    var spokes: [Spoke] = []

    init(arc: Arc = Arc(), radius: Int = 124, spokes: [Spoke] = []) {
        self.arc = arc
        self.radius = radius
        self.spokes = spokes
    }

    enum CodingKeys: String, CodingKey { case arc, radius, spokes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arc = (try? c.decodeIfPresent(Arc.self, forKey: .arc)) ?? Arc()
        radius = (try? c.decodeIfPresent(Int.self, forKey: .radius)) ?? 124
        spokes = (try? c.decodeIfPresent([Spoke].self, forKey: .spokes)) ?? []
    }
}
