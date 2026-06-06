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
    let updater = UpdateChecker()

    private let wheel = WheelController()
    private let summon = Summon()

    /// A hands-free dictation session is active (started at center; the next
    /// summon press stops recording and shows the finish ring).
    private var sessionActive = false

    /// Surrounding context captured when the current dictation began (focus is on
    /// the target field then). Fed to the transcriber as a prompt, and reused as
    /// a function's `{context}` so we don't read it twice.
    private var pendingContext = ""

    /// The profile resolved on the latest summon (honoring `when` conditions), so the
    /// finish ring and `{context}` follow the same one the action wheel was built from.
    private var activeProfile: Profile?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HaloLog.log("Halo launched (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        NSApp.setActivationPolicy(.regular)      // a proper Dock app; the wheel still runs in the background

        wheel.haloProvider = { [weak self] in
            guard let self else { return Halo() }
            self.store.reload()
            let front = NSWorkspace.shared.frontmostApplication
            let frontPID = front?.processIdentifier
            let profile: Profile?
            if let pinned = self.store.profileOverride,
               let chosen = self.store.config.profiles.first(where: { $0.name == pinned }) {
                profile = chosen                                   // manual pick from the menu bar wins
            } else {
                profile = self.store.config.activeProfile(forApp: front?.bundleIdentifier) { [weak self] cond in
                    self?.evaluateWhen(cond, frontPID: frontPID) ?? false
                }
            }
            self.activeProfile = profile
            if self.sessionActive {
                return profile?.finish ?? self.store.config.voice.finish ?? HaloConfig.defaultFinish()
            }
            return profile?.halo ?? self.store.config.defaultHalo
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
        ActionRunner.onFunction = { [weak self] name, vars, provider, inject, capture, done in
            guard let self else { return done(nil) }
            self.runFunction(name: name, vars: vars, provider: provider, inject: inject, capture: capture, done: done)
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
        updater.checkInBackground()          // notify if a newer build has shipped (daily, quiet)
    }

    /// Keep Halo running (wheel + menu bar) when the main window is closed; only
    /// an explicit Quit (⌘Q) stops it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Dictation session

    private func startSession() {
        guard voice.isReady else { return }
        sessionActive = true
        // Capture context now, while the target field still has focus — it biases
        // transcription and feeds `{context}`. (bash sources finish during recording.)
        pendingContext = ""
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let cfg = activeProfile?.context ?? store.config.context ?? store.config.contextConfig(forApp: bundleID)
        captureContext(cfg, vars: [:]) { [weak self] ctx in
            self?.pendingContext = ctx
        }
        voice.startRecording()
        wheel.beginVoiceSession()            // hub stays up as the live recording UI
    }

    /// Summon pressed during a session: you're done talking. Stop recording,
    /// let other audio resume, and transcribe right away so the finish ring can
    /// preview the text before you commit.
    private func finishRecording() {
        voice.stopRecording()
        wheel.markTranscribing()             // hub → "Transcribing…" until the preview lands
        voice.transcribe(prompt: pendingContext) { [weak self] text in self?.wheel.showTranscript(text) }
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

    /// Evaluate a profile's `when` condition for the frontmost app (synchronous,
    /// shell-free, so it's safe on the summon path): the `process` must be running
    /// under `frontPID`, and/or the focused window title must match `titleMatches`.
    private func evaluateWhen(_ when: WhenMatch, frontPID: pid_t?) -> Bool {
        if let proc = when.process, !proc.isEmpty {
            guard let frontPID, ProcessTree.containsDescendant(named: proc, under: frontPID) else { return false }
        }
        if let pattern = when.titleMatches, !pattern.isEmpty {
            let title = AXContext.focusedWindowTitle()
            guard let re = try? NSRegularExpression(pattern: pattern),
                  re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil else { return false }
        }
        return true
    }

    /// Capture `{context}` per a resolved `ContextConfig`: a `bash` command's stdout
    /// (e.g. `tmux capture-pane`), else lines before the caret via Accessibility.
    /// Calls back on the main queue with the text (or "" — never fails).
    private func captureContext(_ cfg: ContextConfig, vars: [String: String], done: @escaping (String) -> Void) {
        if let command = cfg.bash, !command.isEmpty {
            runBash(command, inject: false, capture: true, vars: vars) { done($0 ?? "") }
        } else {
            done(AXContext.linesBeforeCaret(cfg.lines ?? 12))
        }
    }

    /// Call a function. Resolve it from `functions:` (an unknown name is treated as
    /// a literal instruction), interpolate its `prompt` with the function's variable
    /// defaults overlaid by the call-site `vars` (which include `{transcript}`),
    /// resolve the engine (call override → function's → default), look up any key in
    /// the Keychain, and call the endpoint. The dictation is the input.
    /// **Fail-safe:** with no provider configured, or on error / empty reply, fall
    /// back to the raw transcript so words are never lost. `inject` types the reply
    /// back; `capture` means a later step needs it, so we wait (mirrors `runBash`).
    private func runFunction(name: String, vars: [String: String], provider providerOverride: String?,
                             inject: Bool, capture: Bool, done: @escaping (String?) -> Void) {
        let fn = store.config.functions?[name]

        // Lazily resolve `{context}` the first time a function needs it: reuse what
        // was captured at dictation start (focus was guaranteed there); if there's no
        // session, capture now for the frontmost app. Then re-enter with it filled in.
        if (fn?.prompt ?? name).contains("{context}"), vars["context"] == nil {
            let supply: (@escaping (String) -> Void) -> Void = { complete in
                if self.sessionActive { complete(self.pendingContext) }
                else {
                    let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    self.captureContext(self.store.config.contextConfig(forApp: bundleID), vars: vars, done: complete)
                }
            }
            supply { [weak self] ctx in
                var v = vars; v["context"] = ctx
                self?.runFunction(name: name, vars: v, provider: providerOverride,
                                  inject: inject, capture: capture, done: done)
            }
            return
        }
        var resolvedVars = fn?.variables ?? [:]                          // defaults…
        resolvedVars.merge(vars) { _, callValue in callValue }           // …overlaid by the call site
        let system = Function.interpolate(fn?.prompt ?? name, resolvedVars)   // unknown name → use it verbatim
        let user = resolvedVars["transcript"] ?? ""                      // the dictation is the input
        let providerName = providerOverride ?? fn?.provider

        guard let resolved = store.config.llm?.provider(named: providerName) else {
            // Nothing configured → degrade to passing the input through untouched.
            if inject, !user.isEmpty { voice.inject(user) }
            return done(capture ? user : nil)
        }
        let key = resolved.keyRef.flatMap { Keychain.string(forRef: $0) }
        let provider = LLMClient.Provider(baseURL: resolved.baseURL, model: resolved.model, apiKey: key,
                                          thinking: resolved.thinking ?? true)
        let temperature = fn?.temperature ?? 0.2

        if !capture {
            // inject-only: keep the chain moving; type the reply whenever it lands.
            done(nil)
            LLMClient.complete(provider: provider, system: system, user: user, temperature: temperature) { [weak self] result in
                let text = (try? result.get()).flatMap { $0.isEmpty ? nil : $0 } ?? user   // fall back to raw
                DispatchQueue.main.async {
                    if inject, !text.isEmpty { self?.voice.inject(text) }
                }
            }
            return
        }
        // capture: a later step needs this value, so wait for it.
        LLMClient.complete(provider: provider, system: system, user: user, temperature: temperature) { [weak self] result in
            let text = (try? result.get()).flatMap { $0.isEmpty ? nil : $0 } ?? user
            DispatchQueue.main.async {
                if inject, !text.isEmpty { self?.voice.inject(text) }
                done(text)
            }
        }
    }

    private func endSession() {
        sessionActive = false
        wheel.endVoiceSession()
    }

}
