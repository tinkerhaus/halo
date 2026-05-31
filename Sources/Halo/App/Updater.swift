import Observation
import Sparkle

/// Thin wrapper around Sparkle's updater. Halo ships un-notarized (self-signed),
/// so Gatekeeper can't vouch for updates — but Sparkle verifies every update with
/// its own **Ed25519** key (`SUPublicEDKey` in Info.plist), independent of Apple.
/// The feed lives at `SUFeedURL` (the appcast on the product site).
///
/// `SPUStandardUpdaterController(startingUpdater: true)` starts the background
/// update cycle; the menu's "Check for Updates…" calls `checkForUpdates`.
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation? = nil

    /// Mirrors the updater's `canCheckForUpdates` so the menu item disables itself
    /// while a check is already in flight.
    var canCheck = true

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            self?.canCheck = updater.canCheckForUpdates
        }
    }

    func checkForUpdates() { controller.updater.checkForUpdates() }
}
