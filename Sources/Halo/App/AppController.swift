import AppKit

/// Owns Halo's lifecycle. A menu-bar *accessory* (no Dock icon) that listens for
/// the summon button, presents the wheel, and runs dictation.
///
/// Dictation is config-driven: the wheel fires `dictate`/`send`/`cancel`/`undo`
/// verbs (composed in `config.yaml`), and this controller is where those verbs
/// actually touch `Voice` and the recording hub.
final class AppController: NSObject, NSApplicationDelegate {
    let store = HaloStore()
    let voice = Voice()
    let permissions = Permissions()

    private let wheel = WheelController()
    private let summon = Summon()

    /// A hands-free dictation session is active (started at center; the next
    /// summon press stops recording and shows the finish ring).
    private var sessionActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)      // a proper Dock app; the wheel still runs in the background

        wheel.haloProvider = { [weak self] in
            guard let self else { return Halo() }
            self.store.reload()
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return self.sessionActive ? self.store.config.finish(forApp: bundleID)
                                      : self.store.halo(forApp: bundleID)
        }
        wheel.canRecord = { [weak self] in self?.voice.isReady ?? false }
        wheel.hasSession = { [weak self] in self?.sessionActive ?? false }
        wheel.levelProvider = { [weak self] in self?.voice.currentLevel() ?? 0 }

        // Dictation verbs — composed in config, executed here.
        ActionRunner.onDictate = { [weak self] in self?.startSession() }
        ActionRunner.onSend = { [weak self] done in
            guard let self else { return done() }
            self.send(done)
        }
        ActionRunner.onCancel = { [weak self] in self?.cancelSession() }
        ActionRunner.onUndo = { [weak self] in self?.voice.undoLast() }
        ActionRunner.onActed = { [weak self] in self?.voice.clearUndo() }

        summon.button = { [weak self] in self?.store.summonButton ?? 4 }
        summon.onPress = { [weak self] in
            guard let self else { return }
            self.wheel.present()                 // finish ring if a session is active, else the action wheel
            if self.sessionActive { self.finishRecording() }
        }
        summon.onRelease = { [weak self] in self?.wheel.release() }
        summon.start()

        // After the user records a new summon button, ignore the recording click itself.
        NotificationCenter.default.addObserver(forName: .haloSummonButtonRecorded, object: nil, queue: .main) { [weak self] _ in
            self?.summon.rearmOnNextPress()
        }

        voice.prepare()                      // load the model (downloads on first run)
    }

    /// Keep Halo running (wheel + menu bar) when the main window is closed; only
    /// an explicit Quit (⌘Q) stops it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Dictation session

    private func startSession() {
        guard voice.isReady else { return }
        sessionActive = true
        voice.startRecording()
        wheel.beginVoiceSession()            // hub stays up as the live recording UI
    }

    /// Summon pressed during a session: you're done talking. Stop recording,
    /// let other audio resume, and transcribe right away so the finish ring can
    /// preview the text before you commit.
    private func finishRecording() {
        voice.stopRecording()
        wheel.markTranscribing()             // hub → "Transcribing…" until the preview lands
        voice.transcribe { [weak self] text in self?.wheel.showTranscript(text) }
    }

    /// `send`: inject the (already-shown) transcript — waiting if it's somehow not
    /// transcribed yet — then continue the step list (e.g. a trailing Return).
    private func send(_ done: @escaping () -> Void) {
        voice.whenTranscriptReady { [weak self] text in
            self?.voice.inject(text)
            self?.endSession()
            done()
        }
    }

    private func cancelSession() {
        voice.cancel()
        endSession()
    }

    private func endSession() {
        sessionActive = false
        wheel.endVoiceSession()
    }

}
