import SwiftUI

/// The wheel: a dark hub at the cursor with spokes fanned across the arc. Purely
/// a render of `WheelModel`; selection is computed by the controller from the
/// cursor angle, so this view never handles input.
struct WheelView: View {
    let model: WheelModel

    /// 0 → spokes collapsed at the hub, 1 → fully fanned out. Springs to 1 each
    /// time a level appears (the bloom-in).
    @State private var reveal: CGFloat = 1

    private let canvas: CGFloat = 380
    private let hub: CGFloat = 104
    private let spokeSize: CGFloat = 64

    private let accent = LinearGradient(
        colors: [Color(red: 0.55, green: 0.50, blue: 0.98), Color(red: 0.40, green: 0.72, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            hubView
                .frame(width: hub, height: hub)
                .scaleEffect(0.82 + 0.18 * reveal)
                .opacity(Double(min(1, reveal * 1.6)))
                .position(centerPoint)

            if !model.recording {
                ForEach(model.spokes) { spoke in
                    spokeView(spoke)
                        .scaleEffect(reveal)
                        .opacity(Double(reveal))
                        .position(position(for: spoke))
                }
            }
        }
        .frame(width: canvas, height: canvas)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: model.highlighted)
        .onChange(of: model.revealID) { _, _ in bloom() }
        .onChange(of: model.collapseID) { _, _ in collapse() }
    }

    private var centerPoint: CGPoint { CGPoint(x: canvas / 2, y: canvas / 2) }

    /// Spoke position, slid out from the hub by `reveal` (0 → at hub, 1 → fanned).
    private func position(for spoke: WheelSpoke) -> CGPoint {
        let theta: Double = spoke.id < model.angles.count ? model.angles[spoke.id].radians : -.pi / 2
        let r = Double(model.radius) * Double(reveal)
        return CGPoint(x: Double(canvas) / 2 + r * cos(theta),
                       y: Double(canvas) / 2 + r * sin(theta))
    }

    /// Spokes spring out from the hub when a level appears.
    private func bloom() {
        reveal = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { reveal = 1 }
    }

    /// Spokes retract into the hub as the wheel dismisses.
    private func collapse() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { reveal = 0 }
    }

    private var hubView: some View {
        let h = model.highlighted
        return VStack(spacing: 4) {
            if model.recording {
                Image(systemName: "waveform").font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.45))
                Text("Recording…").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            } else if model.modelLoading {
                Image(systemName: "arrow.down.circle.dotted").font(.system(size: 20, weight: .semibold))
                Text("Loading model…").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else if let h, model.spokes.indices.contains(h) {
                Image(systemName: model.spokes[h].glyph).font(.system(size: 21, weight: .semibold))
                Text(model.spokes[h].label).font(.system(size: 13, weight: .bold, design: .rounded))
            } else if model.inWedge {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold))
                Text("Release to cancel").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else if model.depth > 0 {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 20, weight: .semibold))
                Text("Hold to go back").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else {
                Image(systemName: "mic.fill").font(.system(size: 20, weight: .semibold))
                Text("Release to dictate").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .frame(width: hub, height: hub)
        .background(Circle().fill(Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.97)))
        .overlay(Circle().strokeBorder(model.inWedge ? AnyShapeStyle(.white.opacity(0.25))
                                                      : AnyShapeStyle(accent.opacity(h == nil ? 0.55 : 0.95)),
                                       lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
    }

    private func spokeView(_ spoke: WheelSpoke) -> some View {
        let isHot = model.highlighted == spoke.id
        return VStack(spacing: 3) {
            Image(systemName: spoke.glyph).font(.system(size: 18, weight: .semibold))
            Text(spoke.label).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(width: spokeSize, height: spokeSize)
        .background(Circle().fill(isHot ? AnyShapeStyle(accent)
                                        : AnyShapeStyle(Color(red: 0.14, green: 0.15, blue: 0.19).opacity(0.97))))
        .overlay(Circle().strokeBorder(.white.opacity(spoke.isWell ? 0.30 : 0.0), lineWidth: 1).padding(-3.5))
        .shadow(color: .black.opacity(0.45), radius: isHot ? 14 : 7, y: 3)
        .scaleEffect(isHot ? 1.42 : 1)
        .zIndex(isHot ? 1 : 0)
    }
}
