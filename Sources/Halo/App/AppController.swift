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
        ActionRunner.transcript = { [weak self] completion in
            guard let self, self.sessionActive else { return completion("") }
            self.voice.whenTranscriptReady(completion)        // the dictation for $HALO_TRANSCRIPT
        }
        ActionRunner.hasSession = { [weak self] in self?.sessionActive ?? false }
        ActionRunner.endSession = { [weak self] in self?.endSession() }
        ActionRunner.onBash = { [weak self] command, inject, capture, vars, done in
            guard let self else { return done(nil) }
            self.runBash(command, inject: inject, capture: capture, vars: vars, done: done)
        }

        Sounds.shared.isEnabled = { [weak self] in self?.store.config.sounds ?? true }

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
            Sounds.shared.play(.send)
            self?.endSession()
            done()
        }
    }

    private func cancelSession() {
        voice.cancel()
        Sounds.shared.play(.cancel)
        endSession()
    }

    /// Run a `bash` step. Step vars are passed as environment variables — the
    /// dictation as `$HALO_TRANSCRIPT`, any saved outputs as `$name` (never
    /// interpolated, so quotes/newlines are safe) — through a **login shell** so the
    /// user's PATH and tools resolve. `inject` types stdout back; `capture` means a
    /// later step needs the stdout, so we wait and return it.
    private func runBash(_ command: String, inject: Bool, capture: Bool, vars: [String: String],
                         done: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            var env = ProcessInfo.processInfo.environment
            for (key, value) in vars { env[key == "TRANSCRIPT" ? "HALO_TRANSCRIPT" : key] = value }
            process.environment = env

            let wantsOutput = inject || capture
            let pipe = Pipe()
            if wantsOutput { process.standardOutput = pipe }
            do { try process.run() } catch { DispatchQueue.main.async { done(nil) }; return }
            guard wantsOutput else { DispatchQueue.main.async { done(nil) }; return }

            if !capture {
                // inject-only: keep the chain moving; type the output whenever it lands.
                DispatchQueue.main.async { done(nil) }
                let out = AppController.readToEnd(pipe, process)
                if inject, !out.isEmpty { DispatchQueue.main.async { self?.voice.inject(out) } }
                return
            }
            // capture: a later step needs this value, so wait for it.
            let out = AppController.readToEnd(pipe, process)
            DispatchQueue.main.async {
                if inject, !out.isEmpty { self?.voice.inject(out) }
                done(out)
            }
        }
    }

    private static func readToEnd(_ pipe: Pipe, _ process: Process) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func endSession() {
        sessionActive = false
        wheel.endVoiceSession()
    }

}
