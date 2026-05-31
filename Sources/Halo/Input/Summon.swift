import AppKit

/// Watches the configured mouse button and reports press / release. Listens two
/// ways and de-dupes: a `CGEventTap` (which can *consume* the button so it won't
/// also do back/forward) and `MouseHID` (which catches buttons that drivers like
/// Logitech Options+ intercept before they become events). Needs Accessibility
/// (tap) and Input Monitoring (HID).
final class Summon {
    /// Which `NSEvent` button summons the wheel. Read fresh each event.
    var button: () -> Int = { 4 }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pressed = false          // de-dupes tap vs HID
    private var suppressUntilRelease = false   // skip the click used to record a new summon button

    /// After the user records a new summon button, the click they used is still
    /// down — ignore its press *and* release so the wheel only fires from the
    /// next, fresh press.
    func rearmOnNextPress() { suppressUntilRelease = true }

    func start() {
        startTap()
        MouseHID.shared.start()
        MouseHID.shared.subscribe { [weak self] button, pressed in
            guard let self, button >= 2, button == self.button() else { return }   // never left/right
            pressed ? self.beginPress() : self.endPress()
        }
    }

    private func beginPress() {
        guard !suppressUntilRelease else { return }   // still the recording click — wait for a fresh press
        guard !pressed else { return }
        pressed = true; onPress?()
    }

    private func endPress() {
        if suppressUntilRelease { suppressUntilRelease = false; return }   // recording click released → now armed
        guard pressed else { return }
        pressed = false; onRelease?()
    }

    // MARK: - Event tap (consumes the button when it reaches us as an event)

    private func startTap() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                Unmanaged<Summon>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let configured = button()
        guard configured >= 2,
              Int(event.getIntegerValueField(.mouseEventButtonNumber)) == configured else {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .otherMouseDown: DispatchQueue.main.async { self.beginPress() }; return nil
        case .otherMouseUp:   DispatchQueue.main.async { self.endPress() };   return nil
        default:              return Unmanaged.passUnretained(event)
        }
    }
}
