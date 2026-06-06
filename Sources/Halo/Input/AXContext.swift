import ApplicationServices

/// Reads the text immediately before the caret in whatever control currently has
/// focus, via the Accessibility API — the surrounding context Halo can feed to the
/// transcriber (to bias spelling/vocabulary) and to a function's `{context}`.
///
/// Works wherever the app exposes its text to AX (TextEdit, Mail, Notes, most native
/// fields). Returns "" when it doesn't (terminals, many Electron apps) — callers then
/// just proceed without context. Needs Accessibility, which Halo already holds for
/// keystroke synthesis; if it's somehow not trusted, this returns "" too.
enum AXContext {
    /// Up to `lines` lines of text before the caret in the focused element ("" if none).
    static func linesBeforeCaret(_ lines: Int) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let system = AXUIElementCreateSystemWide()
        guard let element = copyElement(system, kAXFocusedUIElementAttribute) else { return "" }

        // The control's full text.
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String, !text.isEmpty else { return "" }
        let ns = text as NSString

        // Caret = start of the selected range (UTF-16 offset), if the app exposes it.
        var caret = ns.length
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rr = rangeRef, CFGetTypeID(rr) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rr as! AXValue, .cfRange, &range), range.location >= 0, range.location <= ns.length {
                caret = range.location
            }
        }

        let before = ns.substring(to: caret)
        let tail = before.components(separatedBy: "\n").suffix(max(1, lines)).joined(separator: "\n")
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The title of the frontmost app's focused window ("" if unavailable). For
    /// terminals this is the active tab/surface's title — e.g. Claude Code writes
    /// its current task there (with a braille spinner glyph while working).
    static func focusedWindowTitle() -> String {
        guard AXIsProcessTrusted() else { return "" }
        let system = AXUIElementCreateSystemWide()
        guard let app = copyElement(system, kAXFocusedApplicationAttribute),
              let window = copyElement(app, kAXFocusedWindowAttribute) else { return "" }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String else { return "" }
        return text
    }

    /// Copy a child `AXUIElement` attribute (e.g. the focused element), type-checked.
    private static func copyElement(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &ref) == .success,
              let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() else { return nil }
        return (r as! AXUIElement)
    }
}
