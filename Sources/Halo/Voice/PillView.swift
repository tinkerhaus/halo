import SwiftUI

/// A small floating capsule shown during a hands-free dictation session — the
/// wheel is gone by then, so this is the feedback. Reads `Voice.status` live.
struct PillView: View {
    let voice: Voice

    var body: some View {
        HStack(spacing: 9) {
            switch voice.status {
            case .transcribing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing…").foregroundStyle(.white.opacity(0.85))
            default:   // recording / everything else while the pill is up
                Circle().fill(Color(red: 1.0, green: 0.35, blue: 0.45))
                    .frame(width: 9, height: 9)
                Text("Listening — press to stop").foregroundStyle(.white.opacity(0.85))
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule(style: .continuous).fill(Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.97)))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .fixedSize()
    }
}
