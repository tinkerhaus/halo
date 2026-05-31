import SwiftUI

/// Placeholder settings shell. The real content — the wheel editor, profiles,
/// sounds, voice — lands as those subsystems come online.
struct SettingsView: View {
    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 10) {
                Image(systemName: "circle.dotted.circle")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Halo")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Summon a wheel of commands at your cursor.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Halo's signature dark, faintly-lit backdrop.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.10).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.55, green: 0.5, blue: 0.98).opacity(0.18), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 520).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.40, green: 0.7, blue: 0.98).opacity(0.14), .clear],
                           center: .bottomTrailing, startRadius: 20, endRadius: 600).ignoresSafeArea()
        }
    }
}
