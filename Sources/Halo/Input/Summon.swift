import AppKit

/// Watches a configured mouse button and reports press / release. It *consumes*
/// the button while bound, so summoning the wheel doesn't also fire the button's
/// normal job (back / forward / etc.). Requires Accessibility permission.
final class Summon {
    /// `NSEvent` button number: 2 = middle, 3 = back (side), 4 = forward (side), …
    var button: Int = 4
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let summon = Unmanaged<Summon>.fromOpaque(refcon!).takeUnretainedValue()
                return summon.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that blocks too long — just re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard Int(event.getIntegerValueField(.mouseEventButtonNumber)) == button else {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .otherMouseDown: DispatchQueue.main.async { self.onPress?() }; return nil
        case .otherMouseUp:   DispatchQueue.main.async { self.onRelease?() }; return nil
        default:              return Unmanaged.passUnretained(event)
        }
    }
}
