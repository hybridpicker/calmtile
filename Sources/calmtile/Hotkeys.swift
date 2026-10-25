import AppKit
import CoreGraphics

/// Global key interception. A matching key is swallowed (the focused app never sees it);
/// `handler` returns false to let the event through (pause mode, passthrough apps, no neighbour to focus).
///
/// The tap runs on its own thread, so a busy main thread (Accessibility calls into an app that does not answer)
/// can never stall it: macOS disables a tap whose callback takes too long and every key would reach the apps
/// (`⌘1` would switch Chrome's tab instead of the workspace). Decisions are still made on the main thread, but
/// waited for only briefly; after that the key is handled by a default and the action runs once the main thread
/// is free again.
final class HotkeyTap {
    /// Decides on the main thread whether to swallow the key. `late` is true when the decision comes after the
    /// key has already been let through.
    var handler: ((Action, _ late: Bool) -> Bool)?
    /// Mouse events, on the main thread; return true to swallow. Only consulted for down/drag/up of the left and
    /// right button while the mouse modifier is held or a drag is in progress.
    var mouseHandler: ((CGEventType, CGPoint, CGEventFlags) -> Bool)?
    /// Told on the main thread, without waiting, of every left or right mouse-down.
    var onClick: (() -> Void)?

    private let lock = NSLock()
    private var _table = [KeyCombo: Action]()
    private var _mouseModifier: Mods?
    private var _dragActive = false
    private var _suspendMouse = false
    private var tap: CFMachPort?
    private var thread: Thread?

    /// Bindings; replaced on the main thread, read on the tap thread.
    var table: [KeyCombo: Action] {
        get { lock.lock(); defer { lock.unlock() }; return _table }
        set { lock.lock(); _table = newValue; lock.unlock() }
    }
    /// Modifier that turns a drag into a window move/resize; nil turns the mouse off.
    var mouseModifier: Mods? {
        get { lock.lock(); defer { lock.unlock() }; return _mouseModifier }
        set { lock.lock(); _mouseModifier = newValue; lock.unlock() }
    }
    /// Set by the controller while a modifier drag is in progress: its drag and up events are swallowed even when
    /// the main thread is too busy to say so.
    var dragActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _dragActive }
        set { lock.lock(); _dragActive = newValue; lock.unlock() }
    }
    /// Set while calmtile itself drives the mouse (moving a window to another desktop).
    var suspendMouse: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _suspendMouse }
        set { lock.lock(); _suspendMouse = newValue; lock.unlock() }
    }

    /// Longest wait for the main thread before a key is handled by its default.
    static let keyTimeout: TimeInterval = 0.25
    /// A key that reaches the main thread later than this is not acted on any more.
    static let staleAfter: TimeInterval = 1.0

    private var _switches = 0
    /// Numbers the workspace keys as they arrive (tap thread); `lastSwitch` is the newest.
    private func nextSwitch() -> Int {
        lock.lock(); defer { lock.unlock() }
        _switches += 1
        return _switches
    }
    private var lastSwitch: Int {
        lock.lock(); defer { lock.unlock() }
        return _switches
    }
    static let mouseTimeout: TimeInterval = 0.15

    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                Log.write("key tap re-enabled after \(type == .tapDisabledByTimeout ? "a timeout" : "user input")")
                return Unmanaged.passUnretained(event)
            }
            if type != .keyDown {
                return me.mouse(type, at: event.location, flags: event.flags) ? nil : Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.eventSourceUserData) == Spaces.ownEventTag { return Unmanaged.passUnretained(event) }   // our own key for the Dock
            let combo = KeyCombo(keyCode: event.getIntegerValueField(.keyboardEventKeycode), mods: Mods(flags: event.flags))
            guard let action = me.table[combo], let h = me.handler else { return Unmanaged.passUnretained(event) }
            let asked = CACurrentMediaTime()
            let switchNumber = action.switchesWorkspace ? me.nextSwitch() : 0
            let swallow = me.onMain(timeout: HotkeyTap.keyTimeout, fallback: action.swallowedWhenLate, what: "\(action)") { late in
                let age = CACurrentMediaTime() - asked
                Profile.key(wait: age, late: late)
                // Keys queued behind a long block of the main thread would otherwise all run at once afterwards
                // (three ⌘N in a row, a switch the user has long given up on). Too old: dropped. Of several
                // workspace keys only the last one counts.
                if late, age > HotkeyTap.staleAfter {
                    Log.write("hotkey \(action) dropped: \(String(format: "%.1f", age)) s late")
                    return action.swallowedWhenLate
                }
                if late, switchNumber != 0, switchNumber != me.lastSwitch {
                    Log.write("hotkey \(action) dropped: a later workspace key is waiting")
                    return true
                }
                return h(action, late)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        let th = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            CFRunLoopRun()
        }
        th.name = "calmtile.keytap"
        th.qualityOfService = .userInteractive
        th.start()
        thread = th
        return true
    }

    /// Mouse events reach the main thread only when they can matter: a click with the mouse modifier held, or any
    /// event while a drag is in progress (a stale drag is also cleared by the next click).
    private func mouse(_ type: CGEventType, at p: CGPoint, flags: CGEventFlags) -> Bool {
        lock.lock()
        let mods = _mouseModifier, dragging = _dragActive, suspended = _suspendMouse
        lock.unlock()
        if type == .leftMouseDown || type == .rightMouseDown, let c = onClick { DispatchQueue.main.async(execute: c) }
        guard !suspended, let h = mouseHandler else { return false }
        switch type {
        case .leftMouseDown, .rightMouseDown:
            guard dragging || (mods != nil && Mods(flags: flags) == mods) else { return false }
            return onMain(timeout: HotkeyTap.mouseTimeout, fallback: false, what: "mouse down") { _ in h(type, p, flags) }
        default:
            guard dragging else { return false }
            return onMain(timeout: HotkeyTap.mouseTimeout, fallback: true, what: "mouse drag") { _ in h(type, p, flags) }
        }
    }

    private final class Pending {
        let lock = NSLock()
        var result: Bool
        var late = false
        init(_ r: Bool) { result = r }
    }

    /// Run `work` on the main thread and wait at most `timeout` for its answer; after that `fallback` decides and
    /// `work` still runs (with `late` set) when the main thread gets to it.
    private func onMain(timeout: TimeInterval, fallback: Bool, what: String, _ work: @escaping (_ late: Bool) -> Bool) -> Bool {
        let p = Pending(fallback)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            p.lock.lock(); let late = p.late; p.lock.unlock()
            let r = work(late)
            p.lock.lock(); p.result = r; p.lock.unlock()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.lock.lock(); p.late = true; p.lock.unlock()
            Log.write("main thread busy: \(what) \(fallback ? "swallowed" : "passed through") by default")
            return fallback
        }
        p.lock.lock(); defer { p.lock.unlock() }
        return p.result
    }
}

private extension Action {
    var switchesWorkspace: Bool {
        switch self {
        case .workspace, .backAndForth: return true
        default: return false
        }
    }

    /// What happens to the key when the main thread does not answer in time: a focus key may still be the app's
    /// (⌘← moves the text cursor when there is no neighbour), everything else is always ours.
    var swallowedWhenLate: Bool {
        if case .focus = self { return false }
        return true
    }
}
