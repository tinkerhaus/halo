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

    private let accentColor = Color(red: 0.55, green: 0.50, blue: 0.98)

    /// A frosted-glass disc that samples the app behind the wheel (behind-window
    /// vibrancy) plus a darkening veil, an optional accent tint for selection, and a
    /// top specular rim. Glyphs/labels sit on top of this.
    @ViewBuilder
    private func frostDisc(tint: Color?, darken: Double, shadowRadius: CGFloat, isWell: Bool = false) -> some View {
        ZStack {
            FrostCircle(material: .hudWindow)
            Circle().fill(.black.opacity(darken))
            if let tint { Circle().fill(tint.opacity(0.5)) }
        }
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06), .clear],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
        .overlay { if isWell { Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1).padding(-3) } }
        .shadow(color: .black.opacity(0.5), radius: shadowRadius, y: 4)
    }

    var body: some View {
        ZStack {
            hubView
                .frame(width: hub, height: hub)
                .scaleEffect(0.82 + 0.18 * reveal)
                .opacity(Double(min(1, reveal * 1.6)))
                .position(centerPoint)

            if !model.recording {           // finish-ring spokes stay visible while transcribing/previewing
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
        return VStack(spacing: 5) {
            if model.recording {
                WaveformView(levels: model.levels, tint: Color(red: 1.0, green: 0.35, blue: 0.45))
                    .frame(width: 72, height: 28)
                Text("Listening…").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            } else if let h, model.spokes.indices.contains(h) {
                Image(systemName: model.spokes[h].glyph).font(.system(size: 21, weight: .semibold))
                Text(model.spokes[h].label).font(.system(size: 13, weight: .bold, design: .rounded))
            } else if model.inWedge {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold))
                Text("Release to cancel").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else if model.modelLoading {
                Image(systemName: "arrow.down.circle.dotted").font(.system(size: 20, weight: .semibold))
                Text("Loading model…").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else if model.finishing {
                Image(systemName: "paperplane.fill").font(.system(size: 19, weight: .semibold))
                Text("Release to send").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            } else {
                Image(systemName: "mic.fill").font(.system(size: 20, weight: .semibold))
                Text("Release to dictate").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .frame(width: hub, height: hub)
        .background(frostDisc(tint: model.inWedge ? .white : nil, darken: 0.34, shadowRadius: 14))
    }

    private func spokeView(_ spoke: WheelSpoke) -> some View {
        let isHot = model.highlighted == spoke.id
        return VStack(spacing: 3) {
            Image(systemName: spoke.glyph).font(.system(size: 18, weight: .semibold))
            Text(spoke.label).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(width: spokeSize, height: spokeSize)
        .background(frostDisc(tint: isHot ? accentColor : nil, darken: 0.20,
                              shadowRadius: isHot ? 14 : 7, isWell: spoke.isWell))
        .scaleEffect(isHot ? 1.42 : 1)
        .zIndex(isHot ? 1 : 0)
    }
}

/// A simple live waveform — recent mic levels (0…1) as centered rounded bars.
struct WaveformView: View {
    let levels: [Float]
    var tint: Color = .white

    var body: some View {
        Canvas { ctx, size in
            guard !levels.isEmpty else { return }
            let count = levels.count
            let slot = size.width / CGFloat(count)
            let barW = max(1.2, slot * 0.55)
            for (i, level) in levels.enumerated() {
                let h = max(2, CGFloat(level) * size.height)
                let x = CGFloat(i) * slot + (slot - barW) / 2
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barW, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(tint))
            }
        }
    }
}

/// The dictation transcript, shown in its own floating panel *above* the wheel —
/// roomy and readable instead of cramped inside the hub. Bottom-anchored, so the
/// bubble sits just above the wheel and grows upward as the text gets longer.
struct TranscriptCaption: View {
    let model: WheelModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if model.transcribing || !model.transcript.isEmpty {
                bubble.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .frame(width: 380, height: 220, alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.transcript)
        .animation(.easeOut(duration: 0.18), value: model.transcribing)
    }

    private var bubble: some View {
        let placeholder = model.transcript.isEmpty
        return Text(placeholder ? "Transcribing…" : model.transcript)
            .font(.system(size: 14, weight: .medium))
            .italic(placeholder)
            .multilineTextAlignment(.center)
            .lineLimit(8)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.white.opacity(placeholder ? 0.6 : 0.95))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: 320)
            .background(
                ZStack {
                    FrostRoundedRect(material: .hudWindow, cornerRadius: 14)
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.32))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            .padding(.bottom, 8)
    }
}
