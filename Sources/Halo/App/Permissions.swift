import AppKit
import AVFoundation
import IOKit.hid
import Observation

extension Notification.Name {
    /// Posted from the menu to (re)open the onboarding window.
    static let haloShowOnboarding = Notification.Name("Halo.showOnboarding")
    /// Posted right after the user records a new summon button, so `Summon`
    /// can ignore the recording click and only fire from the next press.
    static let haloSummonButtonRecorded = Notification.Name("Halo.summonButtonRecorded")
}

/// The three permissions Halo needs. Used to label and route onboarding rows.
enum Permission: CaseIterable {
    case accessibility, inputMonitoring, microphone
}

/// Live permission status, polled on a timer so the onboarding checklist reflects
/// grants made in System Settings without needing a relaunch.
@Observable
final class Permissions {
    private(set) var accessibility = false
    private(set) var inputMonitoring = false
    private(set) var microphone = false

    var allGranted: Bool { accessibility && inputMonitoring && microphone }

    func granted(_ p: Permission) -> Bool {
        switch p {
        case .accessibility:   return accessibility
        case .inputMonitoring: return inputMonitoring
        case .microphone:      return microphone
        }
    }

    @ObservationIgnored private var timer: Timer?

    init() { refresh() }

    func startPolling() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)        // fire even during UI tracking
        timer = t
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        // AXIsProcessTrusted() caches per-process and goes stale, so it never
        // reflects a grant without a relaunch. Creating a session event tap can't
        // be answered from that cache — if it succeeds, Accessibility is live NOW.
        // (Same trick production macOS apps use to update without relaunching.)
        accessibility = AXIsProcessTrusted()
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Prompt for a permission (registers Halo in the System Settings list / shows
    /// the mic dialog) and open the exact pane so the user can flip the toggle.
    func request(_ p: Permission) {
        switch p {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        openSettings(for: p)
    }

    func openSettings(for p: Permission) {
        let anchor: String
        switch p {
        case .accessibility:   anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .microphone:      anchor = "Privacy_Microphone"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
