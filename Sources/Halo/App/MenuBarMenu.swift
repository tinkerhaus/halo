import SwiftUI
import AppKit

/// The status-item menu. Deliberately sparse — Halo is driven by the wheel,
/// not by menus.
struct MenuBarMenu: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(Voice.self) private var voice

    var body: some View {
        Text("Voice: \(voice.statusText)")
        Divider()
        Button("Halo Settings…") { openSettings() }
        Divider()
        Button("Quit Halo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
