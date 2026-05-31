import Foundation

/// Performs an `Action`'s steps in order, spacing them so each paste / keystroke
/// lands before the next. Local and deterministic.
enum ActionRunner {
    /// Supplies recent clipboard entries for `.paste` steps (0 = latest).
    /// Wired up once a clipboard history monitor exists.
    static var clipboard: (Int) -> String? = { _ in nil }

    static func run(_ action: Action) { run(action.steps[...]) }

    private static func run(_ steps: ArraySlice<Step>) {
        guard let step = steps.first else { return }
        let rest = steps.dropFirst()
        let settle = perform(step)
        if rest.isEmpty { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { run(rest) }
    }

    /// Perform one step; returns seconds to wait before the next.
    private static func perform(_ step: Step) -> Double {
        switch step {
        case let .key(code, modifiers):
            Keyboard.press(code, modifiers.cgEventFlags)
            return 0.04
        case let .text(text):
            Keyboard.type(text)
            return 0.4                       // clear the paste-restore window
        case let .paste(recent):
            if let text = clipboard(recent) { Keyboard.type(text) }
            return 0.4
        case let .pause(milliseconds):
            return Double(max(0, milliseconds)) / 1000
        }
    }
}
