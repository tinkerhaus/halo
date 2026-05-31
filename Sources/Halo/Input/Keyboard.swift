import AppKit

/// Low-level keystroke synthesis into the frontmost app. Requires Accessibility
/// permission to post events.
enum Keyboard {
    /// Press a key with the given modifiers (a chord like ⌘S, ⌃C, ⇧⇥, an arrow…).
    static func press(_ code: UInt16, _ flags: CGEventFlags) {
        releaseModifiers()
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Type literal text via paste-and-restore — works in any field regardless
    /// of keyboard layout.
    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        releaseModifiers()
        press(9, .maskCommand)   // ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { restore(pb, saved) }
    }

    /// Clear any modifier that might still be (synthetically) held, so the next
    /// keystroke is read cleanly.
    static func releaseModifiers() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for code: UInt16 in [54, 55, 56, 58, 59, 60, 61, 62, 63] {
            CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Pasteboard snapshot / restore

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { dict[type] = item.data(forType: type) }
            return dict
        }
    }

    private static func restore(_ pb: NSPasteboard, _ items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        pb.writeObjects(items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        })
    }
}
