import AppKit
import CoreGraphics

/// Global key interception. A matching key is swallowed (the focused app never sees it);
/// `handler` returns false to let the event through (pause mode, passthrough apps).
final class HotkeyTap {
    var table = [KeyCombo: Action]()
    var handler: ((Action) -> Bool)?
    /// Mouse events; return true to swallow. Only consulted for down/drag/up of the left and right button.
    var mouseHandler: ((CGEventType, CGPoint, CGEventFlags) -> Bool)?
    private var tap: CFMachPort?

    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type != .keyDown {
                if let h = me.mouseHandler, h(type, event.location, event.flags) { return nil }
                return Unmanaged.passUnretained(event)
            }
            let combo = KeyCombo(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                 mods: Mods(flags: event.flags))
            if let action = me.table[combo], let h = me.handler, h(action) { return nil }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }
}
