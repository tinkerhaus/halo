import SwiftUI
import AppKit

extension Bundle {
    /// Halo's processed-resources bundle, resolved from the running app's
    /// `Contents/Resources` (where `package.sh` places `Halo_Halo.bundle` and the code
    /// signature seals it). We deliberately avoid SwiftPM's generated `Bundle.module`:
    /// that accessor hardcodes the build machine's absolute `.build` path and
    /// `Swift.fatalError`s when the bundle isn't found there — which crashed the shipped
    /// app on launch on every machine but the one it was built on. This degrades to
    /// `.main` instead, so a missing resource merely falls back to a system glyph.
    static let halo: Bundle = {
        Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("Halo_Halo.bundle")) }
            ?? .main
    }()
}

extension NSImage {
    /// The Halo brand mark — the app icon cropped a touch tighter for inline use.
    /// One asset, used for every in-app logo spot (and mirrored on the website).
    static let haloLogo: NSImage = Bundle.halo.url(forResource: "Logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
}

/// The Halo logo at a given size — use this anywhere the brand mark appears.
struct HaloLogo: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: .haloLogo).resizable().frame(width: size, height: size)
    }
}

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
