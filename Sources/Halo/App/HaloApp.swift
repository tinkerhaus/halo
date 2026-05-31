import SwiftUI
import AppKit

/// Halo is a menu-bar agent: it has no main window, just a status item and a
/// settings window. The wheel itself is summoned over whatever app you're in.
@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    /// Halo's branded menu-bar glyph — bigger, and tinted Halo purple (a fixed
    /// color, so it's not auto-tinted black/white by macOS).
    private static let menuBarIcon: NSImage = {
        guard let base = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap({ NSImage(contentsOf: $0) }) else {
            return NSImage(systemSymbolName: "circle", accessibilityDescription: "Halo")!
        }
        let size = NSSize(width: 22, height: 22)
        let tint = NSColor(red: 0.62, green: 0.50, blue: 0.98, alpha: 1)   // Halo purple
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect.insetBy(dx: -5, dy: -5))   // scale the ring up, crop the padding
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environment(controller.voice)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }

        SwiftUI.Settings {
            SettingsView()
                .environment(controller.store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
