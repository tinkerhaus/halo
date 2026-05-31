import SwiftUI
import AppKit

/// The status-item menu. Deliberately sparse — Halo is driven by the wheel,
/// not by menus.
struct MenuBarMenu: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(Voice.self) private var voice
    @Environment(HaloStore.self) private var store

    var body: some View {
        Text("Voice: \(voice.statusText)")
        if store.configError != nil {
            Text("⚠︎ Config invalid — using defaults")
        }
        Divider()
        Button("Open Halo") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Reset Config to Defaults…") { confirmReset() }
        Divider()
        Button("Quit Halo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Confirm before overwriting the user's config (an accessory app must
    /// activate to bring the alert to the front).
    private func confirmReset() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset Halo config to defaults?"
        alert.informativeText = "This overwrites config.yaml with the built-in defaults. Your current config will be lost."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.resetToStarter() }
    }
}
