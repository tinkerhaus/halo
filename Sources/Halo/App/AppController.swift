import AppKit

/// Owns Halo's lifecycle. A menu-bar *accessory* (no Dock icon) that listens for
/// the summon button and presents the wheel over the frontmost app.
final class AppController: NSObject, NSApplicationDelegate {
    let store = HaloStore()

    private let wheel = WheelController()
    private let summon = Summon()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // The wheel reflects the frontmost app's profile, re-reading the config
        // so hand/AI edits to halo.json take effect on the next summon.
        wheel.haloProvider = { [weak self] in
            self?.store.reload()
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return self?.store.halo(forApp: bundleID) ?? Configuration.starter().fallback
        }

        summon.onPress = { [weak self] in self?.wheel.present() }
        summon.onRelease = { [weak self] in self?.wheel.release() }
        summon.start()

        requestAccessibilityIfNeeded()
    }

    /// Summon + keystroke injection both need Accessibility. Prompt once.
    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
