import Foundation
import IOKit.hid

/// Reads mouse buttons straight from the HID layer. This sits *below* drivers
/// like Logitech Options+, so it still sees physical side-button presses even
/// when that software remaps them — those never surface as `CGEvent`s, which is
/// why an event tap alone misses them.
///
/// Button numbers match `NSEvent` (left 0, right 1, middle 2, back 3, forward 4…)
/// by subtracting 1 from the HID Button usage. Needs **Input Monitoring**.
final class MouseHID {
    static let shared = MouseHID()
    private init() {}

    private var manager: IOHIDManager?
    private var subscribers: [UUID: (_ button: Int, _ pressed: Bool) -> Void] = [:]
    private var lastState: [Int: Bool] = [:]

    func start() {
        guard manager == nil else { return }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<MouseHID>.fromOpaque(ctx).takeUnretainedValue().handle(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
    }

    @discardableResult
    func subscribe(_ handler: @escaping (_ button: Int, _ pressed: Bool) -> Void) -> UUID {
        let id = UUID(); subscribers[id] = handler; return id
    }
    func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_Button) else { return }
        let usage = Int(IOHIDElementGetUsage(element))
        guard usage >= 1 else { return }
        let button = usage - 1
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        guard lastState[button] != pressed else { return }   // collapse duplicate reports
        lastState[button] = pressed
        let subs = subscribers.values
        DispatchQueue.main.async { subs.forEach { $0(button, pressed) } }
    }
}
