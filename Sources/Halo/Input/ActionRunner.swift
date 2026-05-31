import Foundation

/// Performs an `Action`'s steps in order, spacing them so each paste / keystroke
/// lands before the next. Local and deterministic.
///
/// Dictation verbs (`dictate`/`send`/`cancel`/`undo`) are injected hooks, wired by
/// `AppController` — so the runner and the model stay free of Voice/UI types.
/// `send` is asynchronous: it waits for transcription before the following steps
/// run, so `[send, key: return]` types your words *then* hits Return.
///
/// A run carries a `vars` dictionary so steps can pass data forward: a `bash` step
/// with `name:` saves its stdout into `vars`, and every later `bash` step sees the
/// accumulated vars as env vars (the dictation is the built-in `$HALO_TRANSCRIPT`).
/// The transcript is resolved once per run, and a session that was live when the
/// run started is ended when it finishes.
enum ActionRunner {
    /// Supplies recent clipboard entries for `.paste` steps (0 = latest).
    static var clipboard: (Int) -> String? = { _ in nil }

    static var onDictate: () -> Void = {}                       // start a voice session
    static var onSend: (@escaping () -> Void) -> Void = { $0() } // inject transcript, then continue
    static var onCancel: () -> Void = {}                        // discard the recording/session
    static var onUndo: () -> Void = {}                          // delete the last injected dictation
    static var onActed: () -> Void = {}                         // a non-undo action ran → invalidate undo

    /// Resolve the current dictation transcript (waiting if it's mid-transcription);
    /// returns "" when no session is active. Called at most once per run.
    static var transcript: (@escaping (String) -> Void) -> Void = { $0("") }
    /// Whether a hands-free dictation session is active.
    static var hasSession: () -> Bool = { false }
    /// End the active dictation session (tear down the recording hub).
    static var endSession: () -> Void = {}
    /// Run a shell command. `capture` ⇒ a later step needs its stdout (wait for it);
    /// `inject` ⇒ type its stdout back. `vars` are exposed as environment variables.
    /// Calls back with the captured stdout (or nil). Wired by `AppController`.
    static var onBash: (_ command: String, _ inject: Bool, _ capture: Bool,
                        _ vars: [String: String], _ done: @escaping (_ output: String?) -> Void) -> Void
        = { _, _, _, _, done in done(nil) }

    static func run(_ action: Action) {
        // Any action other than undo buries the last dictation, so undo goes inert.
        if !action.steps.contains(.verb(.undo)) { onActed() }
        let wasSession = hasSession()
        run(action.steps[...], vars: [:]) {
            // A finish-ring run that didn't end the session itself (e.g. a bash-only
            // spoke) commits it on completion.
            if wasSession, hasSession() { endSession() }
        }
    }

    private static func run(_ steps: ArraySlice<Step>, vars: [String: String], done: @escaping () -> Void) {
        guard let step = steps.first else { return done() }
        let rest = steps.dropFirst()
        perform(step, vars: vars) { newVars in run(rest, vars: newVars, done: done) }
    }

    /// Perform one step, then call `next` with the (possibly updated) vars — after a
    /// settle delay so each paste/keystroke lands before the following one.
    private static func perform(_ step: Step, vars: [String: String],
                                then next: @escaping (_ vars: [String: String]) -> Void) {
        switch step {
        case let .key(code, modifiers):
            Keyboard.press(code, modifiers.cgEventFlags)
            settle(0.04) { next(vars) }
        case let .text(text):
            Keyboard.type(text)
            settle(0.4) { next(vars) }                   // clear the paste-restore window
        case let .paste(recent):
            if let text = clipboard(recent) { Keyboard.type(text) }
            settle(0.4) { next(vars) }
        case let .pause(milliseconds):
            settle(Double(max(0, milliseconds)) / 1000) { next(vars) }
        case let .verb(verb):
            switch verb {
            case .dictate: onDictate(); next(vars)
            case .send:    onSend { settle(0.4) { next(vars) } }   // wait for transcript + paste, then continue
            case .cancel:  onCancel(); next(vars)
            case .undo:    onUndo(); settle(0.04) { next(vars) }
            }
        case let .bash(command, inject, name):
            withTranscript(vars) { v in
                onBash(command, inject, name != nil, v) { output in
                    var nv = v
                    if let name, let output { nv[name] = output }       // save stdout as $name
                    next(nv)
                }
            }
        }
    }

    /// Ensure `vars["TRANSCRIPT"]` is populated — resolved once per run — then continue.
    private static func withTranscript(_ vars: [String: String],
                                       _ completion: @escaping ([String: String]) -> Void) {
        if vars["TRANSCRIPT"] != nil { return completion(vars) }
        transcript { text in
            var v = vars
            v["TRANSCRIPT"] = text
            completion(v)
        }
    }

    private static func settle(_ seconds: Double, _ next: @escaping () -> Void) {
        guard seconds > 0 else { return next() }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: next)
    }
}
