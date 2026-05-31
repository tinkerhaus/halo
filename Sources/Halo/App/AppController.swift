import AppKit

/// Owns Halo's lifecycle. Halo runs as a menu-bar *accessory* (no Dock icon):
/// it sits quietly until summoned. Subsystems — the summon monitor, the wheel
/// presenter, voice — are wired in here as they land.
final class AppController: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
