import Foundation

/// Performs an `Action`'s steps in order, spacing them so each paste / keystroke
/// lands before the next. Local and deterministic.
///
/// Dictation verbs (`dictate`/`send`/`cancel`/`undo`) are injected hooks, wired
/// by `AppController` — so the runner and the model stay free of Voice/UI types.
/// `send` is asynchronous: it waits for transcription before the following steps
/// run, so `[send, key: return]` types your words *then* hits Return.
enum ActionRunner {
    /// Supplies recent clipboard entries for `.paste` steps (0 = latest).
    static var clipboard: (Int) -> String? = { _ in nil }

    static var onDictate: () -> Void = {}                       // start a voice session
    static var onSend: (@escaping () -> Void) -> Void = { $0() } // inject transcript, then continue
    static var onCancel: () -> Void = {}                        // discard the recording/session
    static var onUndo: () -> Void = {}                          // delete the last injected dictation
    static var onActed: () -> Void = {}                         // a non-undo action ran → invalidate undo

    static func run(_ action: Action) {
        // Any action other than undo buries the last dictation, so undo goes inert.
        if !action.steps.contains(.verb(.undo)) { onActed() }
        run(action.steps[...])
    }

    private static func run(_ steps: ArraySlice<Step>) {
        guard let step = steps.first else { return }
        let rest = steps.dropFirst()
        perform(step) {
            guard !rest.isEmpty else { return }
            run(rest)
        }
    }

    /// Perform one step, then call `next` (after a settle delay so each
    /// paste/keystroke lands before the following one).
    private static func perform(_ step: Step, then next: @escaping () -> Void) {
        switch step {
        case let .key(code, modifiers):
            Keyboard.press(code, modifiers.cgEventFlags)
            settle(0.04, next)
        case let .text(text):
            Keyboard.type(text)
            settle(0.4, next)                    // clear the paste-restore window
        case let .paste(recent):
            if let text = clipboard(recent) { Keyboard.type(text) }
            settle(0.4, next)
        case let .pause(milliseconds):
            settle(Double(max(0, milliseconds)) / 1000, next)
        case let .verb(verb):
            switch verb {
            case .dictate: onDictate(); next()
            case .send:    onSend { settle(0.4, next) }   // wait for transcript + paste, then continue
            case .cancel:  onCancel(); next()
            case .undo:    onUndo(); settle(0.04, next)
            }
        }
    }

    private static func settle(_ seconds: Double, _ next: @escaping () -> Void) {
        guard seconds > 0 else { return next() }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: next)
    }
}
