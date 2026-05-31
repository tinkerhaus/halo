import SwiftUI
import AppKit

/// Halo is a menu-bar agent: it has no main window, just a status item and a
/// settings window. The wheel itself is summoned over whatever app you're in.
@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    /// Halo's branded menu-bar glyph, as a template image (auto-tinted by macOS).
    private static let menuBarIcon: NSImage = {
        let image = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "circle", accessibilityDescription: "Halo")!
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
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
