import SwiftUI

/// The wheel: a dark hub at the cursor with spokes fanned across the arc. Purely
/// a render of `WheelModel`; selection is computed by the controller from the
/// cursor angle, so this view never handles input.
struct WheelView: View {
    let model: WheelModel

    private let canvas: CGFloat = 380
    private let hub: CGFloat = 104
    private let spokeSize: CGFloat = 64

    private let accent = LinearGradient(
        colors: [Color(red: 0.55, green: 0.50, blue: 0.98), Color(red: 0.40, green: 0.72, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        let center = CGPoint(x: canvas / 2, y: canvas / 2)
        ZStack {
            hubView.frame(width: hub, height: hub).position(center)

            ForEach(model.spokes) { spoke in
                let theta = spoke.id < model.angles.count ? model.angles[spoke.id].radians : -.pi / 2
                let pos = CGPoint(x: center.x + model.radius * cos(theta),
                                  y: center.y + model.radius * sin(theta))
                spokeView(spoke).position(pos)
            }
        }
        .frame(width: canvas, height: canvas)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: model.highlighted)
    }

    private var hubView: some View {
        let h = model.highlighted
        return VStack(spacing: 4) {
            if let h, model.spokes.indices.contains(h) {
                Image(systemName: model.spokes[h].glyph).font(.system(size: 21, weight: .semibold))
                Text(model.spokes[h].label).font(.system(size: 13, weight: .bold, design: .rounded))
            } else if model.inWedge {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold))
                Text("Release to cancel").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
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
