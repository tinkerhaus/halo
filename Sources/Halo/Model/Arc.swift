import SwiftUI

/// The fan that a halo's spokes occupy. Halo never closes into a full circle —
/// the leftover wedge is always there to release into, which means "cancel".
///
/// Stored in degrees (so it's trivially `Codable`); exposed as `Angle` for views.
/// View space: 0° points right, +90° down, −90° straight up.
struct Arc: Codable, Equatable {
    var spanDegrees: Double = 200
    var centerDegrees: Double = -90

    /// Past this, a halo would close into a ring and lose its cancel wedge.
    static let maxSpanDegrees: Double = 330

    init(spanDegrees: Double = 200, centerDegrees: Double = -90) {
        self.spanDegrees = spanDegrees
        self.centerDegrees = centerDegrees
    }

    enum CodingKeys: String, CodingKey { case spanDegrees, centerDegrees }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spanDegrees = (try? c.decodeIfPresent(Double.self, forKey: .spanDegrees)) ?? 200
        centerDegrees = (try? c.decodeIfPresent(Double.self, forKey: .centerDegrees)) ?? -90
    }

    var span: Angle { .degrees(clampedSpan) }
    var center: Angle { .degrees(centerDegrees) }
    private var clampedSpan: Double { min(max(spanDegrees, 0), Arc.maxSpanDegrees) }

    /// Even angular placements for `count` spokes across the arc.
    func placements(count: Int) -> [Angle] {
        guard count > 0 else { return [] }
        if count == 1 { return [center] }
        let start = centerDegrees - clampedSpan / 2
        let step = clampedSpan / Double(count - 1)
        return (0..<count).map { .degrees(start + Double($0) * step) }
    }

    /// Which spoke the cursor points at, or `nil` if it's in the empty wedge.
    /// Acceptance is measured from the arc's center: anywhere within the fan
    /// (plus half a gap past each end) selects the nearest spoke.
    func selection(forCursor cursor: Angle, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let places = placements(count: count)
        let nearest = places.indices.min {
            abs(Arc.delta(cursor, places[$0])) < abs(Arc.delta(cursor, places[$1]))
        }!
        if count == 1 {
            return abs(Arc.delta(cursor, center)) <= 45 ? nearest : nil
        }
        let half = clampedSpan / 2
        let halfGap = clampedSpan / Double(count - 1) / 2
        return abs(Arc.delta(cursor, center)) <= half + halfGap ? nearest : nil
    }

    /// Shortest signed difference `a − b` in degrees, wrapped to [−180, 180].
    static func delta(_ a: Angle, _ b: Angle) -> Double {
        var d = (a.degrees - b.degrees).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}
