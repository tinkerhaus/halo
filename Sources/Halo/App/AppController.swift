import AppKit

/// Owns Halo's lifecycle. A menu-bar *accessory* (no Dock icon) that listens for
/// the summon button, presents the wheel, and runs dictation per the configured
/// voice mode.
final class AppController: NSObject, NSApplicationDelegate {
    let store = HaloStore()
    let voice = Voice()

    private let wheel = WheelController()
    private let summon = Summon()

    /// A hands-free dictation session is active (started on center release; the
    /// next summon press stops it).
    private var listening = false
    /// The summon release immediately after a "stop" press shouldn't open the wheel.
    private var suppressRelease = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        wheel.haloProvider = { [weak self] in
            self?.store.reload()
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return self?.store.halo(forApp: bundleID) ?? HaloConfig.starter().fallback
        }
        wheel.voiceMode = { [weak self] in self?.store.config.voice.mode ?? .handsFree }
        wheel.canRecord = { [weak self] in self?.voice.isReady ?? false }
        wheel.onCenterHold = { [weak self] in self?.voice.startRecording() }   // push-to-talk: start
        wheel.onCenterRelease = { [weak self] in self?.handleCenterRelease() }
        wheel.levelProvider = { [weak self] in self?.voice.currentLevel() ?? 0 }

        voice.onFinish = { [weak self] in self?.wheel.endVoiceSession() }

        summon.button = { [weak self] in self?.store.summonButton ?? 4 }
        summon.onPress = { [weak self] in
            guard let self else { return }
            if self.listening {              // press during a hands-free session → stop it
                self.stopListeningSession()
                self.suppressRelease = true
            } else {
                self.wheel.present()
            }
        }
        summon.onRelease = { [weak self] in
            guard let self else { return }
            if self.suppressRelease { self.suppressRelease = false; return }
            self.wheel.release()
        }
        summon.start()

        voice.prepare()                      // load the model (downloads on first run)
        requestAccessibilityIfNeeded()
    }

    /// Center was released (hands-free) or push-to-talk hold ended — act per mode.
    private func handleCenterRelease() {
        switch store.config.voice.mode {
        case .pushToTalk:
            voice.stopAndInject()
            wheel.markTranscribing()         // hub shows "Transcribing…" until done
        case .handsFree:
            startListeningSession()
        }
    }

    private func startListeningSession() {
        listening = true
        wheel.beginVoiceSession()            // hub stays up as the live recording UI
        voice.startRecording()
    }

    private func stopListeningSession() {
        listening = false
        voice.stopAndInject()
        wheel.markTranscribing()             // hub → "Transcribing…", hides on voice.onFinish
    }

    /// Summon + keystroke injection need Accessibility. Prompt once.
    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
