import AppKit
import Observation

/// Lightweight update notifier. Halo ships self-signed / un-notarized, so macOS
/// App Management blocks any in-place self-update — so Halo only **notifies**.
///
/// It reads a tiny JSON manifest published next to the site and, when a newer build
/// is out, shows a native alert with a **Download** button that opens the releases
/// page. Nothing is downloaded or installed in-app — the user grabs the new dmg and
/// drags it into Applications, same as the first install.
@Observable
final class UpdateChecker {
    /// Version manifest published alongside the product site (GitHub Pages).
    private static let manifestURL = URL(string: "https://tinkerhaus.github.io/halo/version.json")!
    private static let downloadURL = "https://tinkerhaus.github.io/halo/"
    private static let skippedBuildKey = "HaloSkippedUpdateBuild"
    private static let lastCheckKey = "HaloLastUpdateCheck"
    private static let autoCheckInterval: TimeInterval = 86_400   // at most once a day, in the background

    private struct Manifest: Decodable {
        let shortVersion: String
        let build: Int
        var url: String?
    }

    /// False while a check is in flight, so the menu item can disable itself.
    var canCheck = true

    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Quiet check used on launch / daily: shows UI only when an update is available
    /// (never on "up to date" or a network error).
    func checkInBackground() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < Self.autoCheckInterval { return }
        check(userInitiated: false)
    }

    /// Menu "Check for Updates…": always reports the result, including up-to-date.
    func checkForUpdates() { check(userInitiated: true) }

    private func check(userInitiated: Bool) {
        guard canCheck else { return }
        canCheck = false
        var request = URLRequest(url: Self.manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData      // always see the freshest manifest
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.canCheck = true
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                guard let data, let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                    if userInitiated { self.present(title: "Couldn’t check for updates",
                                                    text: "Please check your internet connection and try again.") }
                    return
                }
                self.handle(manifest, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(_ manifest: Manifest, userInitiated: Bool) {
        guard manifest.build > currentBuild else {
            if userInitiated {
                present(title: "You’re up to date", text: "Halo \(currentShortVersion) is the latest version.")
            }
            return
        }
        // On automatic checks, honor a previously skipped build; a manual check always shows.
        if !userInitiated, UserDefaults.standard.integer(forKey: Self.skippedBuildKey) == manifest.build { return }
        presentUpdate(manifest)
    }

    private func presentUpdate(_ manifest: Manifest) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Halo \(manifest.shortVersion) is available"
        alert.informativeText = "You have \(currentShortVersion). Download the new version and drag it into your Applications folder to update."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: manifest.url ?? Self.downloadURL) { NSWorkspace.shared.open(url) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(manifest.build, forKey: Self.skippedBuildKey)
        default:
            break   // Remind Me Later — surfaces again on the next check
        }
    }

    private func present(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
