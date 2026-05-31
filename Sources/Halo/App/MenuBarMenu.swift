import SwiftUI
import AppKit

/// The status-item menu. Deliberately sparse — Halo is driven by the wheel,
/// not by menus.
struct MenuBarMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Halo Settings…") { openSettings() }
        Divider()
        Button("Quit Halo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
