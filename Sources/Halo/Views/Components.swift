import SwiftUI

/// Halo's signature dark, faintly-lit backdrop.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.10).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.55, green: 0.50, blue: 0.98).opacity(0.18), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 520).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.40, green: 0.72, blue: 0.98).opacity(0.14), .clear],
                           center: .bottomTrailing, startRadius: 20, endRadius: 600).ignoresSafeArea()
        }
    }
}

/// Halo's standard grouping container — real Liquid Glass on macOS 26 (lensing the
/// window's own content behind it), a soft translucent panel on older systems.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 12, fallback: AnyShapeStyle(.white.opacity(0.04)))
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
