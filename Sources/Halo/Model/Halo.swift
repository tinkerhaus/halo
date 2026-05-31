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

    // `id` is runtime-only (never serialized), so it must not affect equality —
    // otherwise a freshly-decoded config never equals the in-memory one and the
    // file-watcher's reload/save dedup can never short-circuit (a rewrite loop).
    static func == (a: Spoke, b: Spoke) -> Bool {
        a.label == b.label && a.glyph == b.glyph && a.content == b.content
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
///
/// `center` is what release-at-center fires. When omitted it defaults to
/// dictation (at any depth), resolved by the wheel controller. Backing out of a
/// sub-ring is a separate gesture — rest at the center — so existing configs are
/// unchanged.
struct Halo: Codable, Equatable {
    /// A halo never fans more than this many spokes — past ~7 the flick targets
    /// get too cramped to hit reliably; use a `well` to nest more. The editor
    /// enforces this; a hand-edited config with more still loads (it just can't grow).
    static let maxSpokes = 7

    var arc = Arc()
    var radius: Int = 124            // points from the hub to each spoke
    var spokes: [Spoke] = []
    var center: Action?              // release-at-center action (nil → context default)

    init(arc: Arc = Arc(), radius: Int = 124, spokes: [Spoke] = [], center: Action? = nil) {
        self.arc = arc
        self.radius = radius
        self.spokes = spokes
        self.center = center
    }

    enum CodingKeys: String, CodingKey { case arc, radius, spokes, center }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(arc, forKey: .arc)
        try c.encode(radius, forKey: .radius)
        try c.encode(spokes, forKey: .spokes)
        if let center { try c.encode(center.steps, forKey: .center) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arc = (try? c.decodeIfPresent(Arc.self, forKey: .arc)) ?? Arc()
        radius = (try? c.decodeIfPresent(Int.self, forKey: .radius)) ?? 124
        spokes = (try? c.decodeIfPresent([Spoke].self, forKey: .spokes)) ?? []
        if let steps = try? c.decodeIfPresent([Step].self, forKey: .center) { center = Action(steps) }
    }
}
