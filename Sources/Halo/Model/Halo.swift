import Foundation

/// One selectable item on a halo. A spoke either *performs* an action or *opens*
/// a nested halo (a "well" you dwell into). Recursive via `Content.opens`.
struct Spoke: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String
    var glyph: String            // SF Symbol name
    var content: Content

    enum Content: Codable, Equatable {
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

/// A ring of spokes: the arc they fan across, how far out they sit, and the
/// spokes themselves. Recursive — a spoke may open another `Halo`.
struct Halo: Codable, Equatable {
    var arc = Arc()
    var radius: Double = 124
    var spokes: [Spoke] = []

    init(arc: Arc = Arc(), radius: Double = 124, spokes: [Spoke] = []) {
        self.arc = arc
        self.radius = radius
        self.spokes = spokes
    }
}
