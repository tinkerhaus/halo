import SwiftUI

/// Halo is a menu-bar agent: it has no main window, just a status item and a
/// settings window. The wheel itself is summoned over whatever app you're in.
@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    var body: some Scene {
        MenuBarExtra("Halo", systemImage: "circle.dotted.circle") {
            MenuBarMenu()
        }

        SwiftUI.Settings {
            SettingsView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
