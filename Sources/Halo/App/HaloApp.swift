import SwiftUI
import AppKit

/// Halo is a menu-bar agent: it has no main window, just a status item and a
/// settings window. The wheel itself is summoned over whatever app you're in.
@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    /// Halo's branded menu-bar glyph — a bold ring with a center dot, as a
    /// template image (macOS tints it white/black to match the menu bar).
    private static let menuBarIcon: NSImage = {
        let image = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "circle", accessibilityDescription: "Halo")!
        image.isTemplate = true
        image.size = NSSize(width: 20, height: 20)
        return image
    }()

    var body: some Scene {
        Window("Halo", id: "main") {
            MainWindow()
                .environment(controller.store)
                .environment(controller.voice)
                .environment(controller.permissions)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { controller.updater.checkForUpdates() }
                    .disabled(!controller.updater.canCheck)
            }
        }

        MenuBarExtra {
            MenuBarMenu()
                .environment(controller.voice)
                .environment(controller.store)
                .environment(controller.updater)
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
