import AppKit
import ApplicationServices
import CalmCore

// Private but long-stable API (also used by AeroSpace, yabai, Rectangle): AXUIElement -> CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct AXWin {
    let id: WindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let resizable: Bool
}

enum Screens {
    /// Monitors in Accessibility coordinates (origin top-left of the main display, y down),
    /// usable area only (below the menu bar, beside the Dock). Main display first, then left to right.
    static func monitors() -> [Monitor] {
        let all = NSScreen.screens
        guard let main = all.first else { return [] }
        let mainHeight = main.frame.height
        let ordered = [main] + all.dropFirst().sorted { $0.frame.minX < $1.frame.minX }
        return ordered.enumerated().map { (i, s) in
            let v = s.visibleFrame
            return Monitor(id: i, frame: CGRect(x: v.minX, y: mainHeight - v.maxY, width: v.width, height: v.height))
        }
    }
}

enum Windows {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Longest wait for one Accessibility answer. Set on the system-wide element it is the default for every
    /// element (window elements do not inherit what is set on their application element; without this they wait
    /// the system's 6 s on an app that does not answer, once per attribute).
    static let messagingTimeout: Float = 0.25
    /// How long an app that let a call time out is left alone (its windows keep their last known state): 0.25 s
    /// after one timeout, doubling with every further one up to 4 s. A busy app that answers late once (Terminal
    /// while it opens a window, measured) is back at once; a hung one costs a timeout every few seconds.
    private static func stallPause(after timeouts: Int) -> CFTimeInterval {
        return min(4.0, 0.25 * pow(2.0, Double(max(0, timeouts - 1))))
    }

    static func setDefaultTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    private static var stalledUntil = [pid_t: CFTimeInterval]()
    private static var timeouts = [pid_t: Int]()
    private static var stallLogged = [pid_t: CFTimeInterval]()

    /// The app sent a notification, so it is answering: stop leaving it alone.
    static func alive(_ pid: pid_t) {
        stalledUntil[pid] = nil
        timeouts[pid] = nil
    }

    /// True while `pid` is being left alone after a timeout. Every read and write to its elements returns at once.
    static func isStalled(_ pid: pid_t) -> Bool {
        guard let t = stalledUntil[pid] else { return false }
        if CACurrentMediaTime() < t { return true }
        stalledUntil[pid] = nil
        return false
    }

    private static func pid(of el: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(el, &p)   // local, no round trip
        return p
    }

    /// Run one Accessibility call unless the element's app is stalled; a call that ran into the timeout stalls
    /// the app for a while (`stallPause`), so a hung app costs one timeout per pause instead of one per attribute
    /// and tick. Only a real timeout counts (an app answering "cannot complete" at once is not hung); any answer
    /// in time ends the back-off.
    private static func call(_ el: AXUIElement, _ work: () -> AXError) -> AXError {
        let p = pid(of: el)
        if p != 0, isStalled(p) { return .cannotComplete }
        Profile.ax()
        let t0 = CACurrentMediaTime()
        let err = work()
        guard p != 0 else { return err }
        if err == .cannotComplete, CACurrentMediaTime() - t0 >= Double(messagingTimeout) * 0.8 {
            let now = CACurrentMediaTime()
            let n = (timeouts[p] ?? 0) + 1
            timeouts[p] = n
            stalledUntil[p] = now + stallPause(after: n)
            guard n >= 3, now - (stallLogged[p] ?? 0) > 30 else { return err }   // a hang, once per hang
            stallLogged[p] = now
            Log.write("app \(NSRunningApplication(processIdentifier: p)?.bundleIdentifier ?? String(p)) did not answer \(n) times in a row: left alone for up to 4 s at a time")
        } else if timeouts[p] != nil {
            timeouts[p] = nil
        }
        return err
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var ref: CFTypeRef?
        guard call(el, { AXUIElementCopyAttributeValue(el, name as CFString, &ref) }) == .success else { return nil }
        return ref as? T
    }

    @discardableResult
    private static func set(_ el: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        return call(el) { AXUIElementSetAttributeValue(el, name as CFString, value) }
    }

    /// Windows of each app from the last listing that reached it, handed out again while the app is stalled.
    private static var lastListed = [pid_t: [AXWin]]()

    private static var enabledPids = Set<pid_t>()

    /// Chromium and Electron apps (Chrome, Slack, Teams, VS Code) expose no windows until an assistive
    /// client asks for it; AXManualAccessibility is their documented switch (no UI side effects).
    static func enableAccessibility(_ ax: AXUIElement, pid: pid_t) {
        guard enabledPids.insert(pid).inserted else { return }
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static var regular = [NSRunningApplication]()
    private static var regularAt: CFTimeInterval = -1
    private static var observingWorkspace = false

    /// Running apps with a Dock icon. Walking `runningApplications` and asking each one for its activation policy
    /// cost about 16 ms with ~120 processes (the profile's observe phase, which does nothing else once every app is
    /// observed), and it ran twice per tick. The list only changes when an app
    /// launches, quits or turns into a regular app (which it does on activation), so it is kept until then, and
    /// refreshed every few seconds regardless.
    static func regularApps() -> [NSRunningApplication] {
        if !observingWorkspace {
            observingWorkspace = true
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                         NSWorkspace.didActivateApplicationNotification] {
                nc.addObserver(forName: name, object: nil, queue: .main) { _ in regularAt = -1 }
            }
        }
        let now = CACurrentMediaTime()
        if regularAt < 0 || now - regularAt > 5 {
            regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
            regularAt = now
        }
        return regular
    }

    /// Layer-0 windows the window server draws right now, by owning process: one call for all apps.
    static func onscreenByPid() -> [pid_t: [WindowID]] {
        Profile.ws()
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID),
              let list = (raw as NSArray) as? [[String: Any]] else { return [:] }
        var out = [pid_t: [WindowID]]()
        for w in list where (w["kCGWindowLayer"] as? Int) == 0 {
            guard let pid = w["kCGWindowOwnerPID"] as? Int, let n = w["kCGWindowNumber"] as? Int else { continue }
            out[pid_t(pid), default: []].append(WindowID(n))
        }
        for k in out.keys { out[k]?.sort() }
        return out
    }

    /// What the window server showed of an app when it was last listed, and when that was.
    private static var listedOnscreen = [pid_t: [WindowID]]()
    private static var listedAt = [pid_t: CFTimeInterval]()

    /// The managed windows of every regular app (see `classify`).
    ///
    /// Asking an app for its windows is a round trip to that app's main thread; with apps paged out under memory
    /// pressure each one took 50-250 ms (measured with InDesign, Acrobat, Calendar, Preview), and every tick asked
    /// all of them. An app is asked again only when something can have changed: it sent a notification (`changed`),
    /// the window server shows a different set of its windows (opened, closed, minimized, hidden, another desktop),
    /// or a few seconds have passed (10 s for an app with no windows at all). Otherwise its last answer stands.
    /// `all` asks every app, as right after a desktop switch, when the Accessibility view lags the window server.
    static func list(excluding selfPid: pid_t, ignoring ignored: [String] = [], changed: Set<pid_t> = [], all: Bool = true) -> [AXWin] {
        var out = [AXWin]()
        let apps = regularApps()
            .filter { $0.processIdentifier != selfPid && !ignored.contains($0.bundleIdentifier ?? "") }
        let onscreen = onscreenByPid()
        let now = CACurrentMediaTime()
        for app in apps {
            let pid = app.processIdentifier
            let shown = onscreen[pid] ?? []
            if !all, !changed.contains(pid), let last = lastListed[pid], listedOnscreen[pid] == shown,
               now - (listedAt[pid] ?? 0) < (shown.isEmpty && last.isEmpty ? 10 : 3) {
                out += last
                continue
            }
            let t0 = CACurrentMediaTime()
            defer {
                let dt = CACurrentMediaTime() - t0
                Profile.listed(app.bundleIdentifier ?? "?", dt)
                if dt > 0.5 { Log.write("slow: listing \(app.bundleIdentifier ?? "?") took \(String(format: "%.1f", dt)) s") }
            }
            if isStalled(pid) { out += lastListed[pid] ?? []; continue }
            let ax = AXUIElementCreateApplication(pid)
            enableAccessibility(ax, pid: pid)
            var mine = [AXWin]()
            if let wins: [AXUIElement] = attr(ax, kAXWindowsAttribute) {
                for w in wins {
                    if let win = classify(w, pid: pid, bundleID: app.bundleIdentifier ?? "?") { mine.append(win) }
                }
            }
            // A timeout part way through leaves an incomplete list: keep the last complete one instead.
            if isStalled(pid) { out += lastListed[pid] ?? []; continue }
            lastListed[pid] = mine
            listedOnscreen[pid] = shown
            listedAt[pid] = now
            out += mine
        }
        let living = Set(apps.map { $0.processIdentifier })
        for pid in Array(lastListed.keys) where !living.contains(pid) {
            lastListed[pid] = nil
            listedOnscreen[pid] = nil
            listedAt[pid] = nil
        }
        return out
    }

    /// The managed-window test for one element: a standard, non-minimized, non-fullscreen window with a window id.
    private static func classify(_ w: AXUIElement, pid: pid_t, bundleID: String) -> AXWin? {
        let role: String? = attr(w, kAXRoleAttribute)
        let subrole: String? = attr(w, kAXSubroleAttribute)
        guard role == kAXWindowRole as String, subrole == "AXStandardWindow" else { return nil }
        if let min: Bool = attr(w, kAXMinimizedAttribute), min { return nil }
        if let fs: Bool = attr(w, "AXFullScreen"), fs { return nil }   // native macOS fullscreen: leave alone
        var wid = CGWindowID(0)
        guard call(w, { _AXUIElementGetWindow(w, &wid) }) == .success, wid != 0 else { return nil }
        var settable = DarwinBoolean(false)
        _ = call(w) { AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &settable) }
        // Transient popups and system alerts claim to be standard windows but have no window
        // buttons and cannot be resized: leave them completely alone (never tile, park or move).
        if !settable.boolValue, (attr(w, kAXCloseButtonAttribute) as AXUIElement?) == nil,
           (attr(w, kAXMinimizeButtonAttribute) as AXUIElement?) == nil { return nil }
        return AXWin(id: wid, element: w, pid: pid, bundleID: bundleID, resizable: settable.boolValue)
    }

    /// A window element straight from an Accessibility notification, if it is one calmtile manages (regular app,
    /// not ignored, standard window).
    static func standardWindow(_ el: AXUIElement, ignoring ignored: [String]) -> AXWin? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(el, &pid) == .success, let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular, !ignored.contains(app.bundleIdentifier ?? "") else { return nil }
        return classify(el, pid: pid, bundleID: app.bundleIdentifier ?? "?")
    }

    /// One line per window of every regular app: role, subrole and capabilities, never the title.
    /// Run through `open -a calmtile --stdout <file> --args --dump-windows` (it needs the Accessibility grant).
    static func dump() -> String {
        var lines = [String]()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited && !app.isTerminated {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.5)
            enableAccessibility(ax, pid: app.processIdentifier)
            guard let wins: [AXUIElement] = attr(ax, kAXWindowsAttribute), !wins.isEmpty else {
                var ref: CFTypeRef?
                let err = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &ref)
                if app.activationPolicy == .regular { lines.append("\(app.bundleIdentifier ?? "?") no windows (AX error \(err.rawValue))") }
                continue
            }
            for w in wins {
                let fullscreen: Bool = attr(w, "AXFullScreen") ?? false
                if fullscreen { lines.append("\(app.bundleIdentifier ?? "?") fullscreen window") }
                let role: String = attr(w, kAXRoleAttribute) ?? "?"
                let sub: String = attr(w, kAXSubroleAttribute) ?? "-"
                var settable = DarwinBoolean(false)
                _ = AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &settable)
                let modal: Bool = attr(w, "AXModal") ?? false
                let min: Bool = attr(w, kAXMinimizedAttribute) ?? false
                let hasClose = (attr(w, kAXCloseButtonAttribute) as AXUIElement?) != nil
                let hasMin = (attr(w, kAXMinimizeButtonAttribute) as AXUIElement?) != nil
                let hasFull = (attr(w, kAXFullScreenButtonAttribute) as AXUIElement?) != nil
                let f = frame(of: w)
                lines.append("\(app.bundleIdentifier ?? "?") role=\(role) subrole=\(sub) resizable=\(settable.boolValue) modal=\(modal) min=\(min) close=\(hasClose) minimize=\(hasMin) full=\(hasFull) size=\(f.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?") at=\(f.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "?")")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func title(of el: AXUIElement) -> String? {
        let t: String? = attr(el, kAXTitleAttribute)
        return t
    }

    static func frame(of el: AXUIElement) -> CGRect? {
        guard let p: AXValue = attr(el, kAXPositionAttribute), let s: AXValue = attr(el, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &pos), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// True when two frames agree within a few pixels (apps round and clamp).
    static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        return abs(a.minX - b.minX) <= 3 && abs(a.minY - b.minY) <= 3
            && abs(a.width - b.width) <= 3 && abs(a.height - b.height) <= 3
    }

    static func setFrame(_ el: AXUIElement, _ r: CGRect) {
        var pos = r.origin
        var size = r.size
        // size, position, size: apps clamp the size to the screen they are currently on.
        var codes = [AXError]()
        if let sv = AXValueCreate(.cgSize, &size) { codes.append(set(el, kAXSizeAttribute, sv)) }
        if let pv = AXValueCreate(.cgPoint, &pos) { codes.append(set(el, kAXPositionAttribute, pv)) }
        if let sv = AXValueCreate(.cgSize, &size) { codes.append(set(el, kAXSizeAttribute, sv)) }
        if Log.debug { Log.write("  set -> \(codes.map { $0.rawValue }) now=\(frame(of: el).map { "\($0)" } ?? "?")") }
    }

    /// Apps that snap their size to a grid (Terminal: character cells) come out a few pixels larger than asked
    /// and overlap the neighbouring tile. Ask once more for a size smaller by the overshoot, so the snapped result
    /// stays inside the tile. Larger differences are a minimum size, which the engine handles.
    static func trimOvershoot(_ el: AXUIElement, to want: CGRect) {
        guard let got = frame(of: el) else { return }
        let dw = got.width - want.width, dh = got.height - want.height
        let trimW = dw > 0 && dw <= 8, trimH = dh > 0 && dh <= 8
        guard trimW || trimH else { return }
        var size = CGSize(width: trimW ? want.width - dw : want.width, height: trimH ? want.height - dh : want.height)
        guard let sv = AXValueCreate(.cgSize, &size) else { return }
        set(el, kAXSizeAttribute, sv)
        if Log.debug { Log.write("  trimmed overshoot \(Int(dw))x\(Int(dh)) -> now=\(frame(of: el).map { "\($0)" } ?? "?")") }
    }

    static func setPosition(_ el: AXUIElement, _ p: CGPoint) {
        var pos = p
        if let pv = AXValueCreate(.cgPoint, &pos) {
            let e = set(el, kAXPositionAttribute, pv)
            if Log.debug { Log.write("  setPosition \(p) -> err=\(e.rawValue)") }
        }
    }

    static func setSize(_ el: AXUIElement, _ s: CGSize) {
        var size = s
        if let sv = AXValueCreate(.cgSize, &size) { set(el, kAXSizeAttribute, sv) }
    }

    /// Mission Control (also App Exposé, Launchpad) puts full-screen Dock windows above everything. One such
    /// window is always there; two or more mean an overview is open (measured on macOS 26: 1 idle, 3 open).
    static func overviewOpen() -> Bool {
        Profile.ws()
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID),
              let list = (raw as NSArray) as? [[String: Any]] else { return false }
        var n = 0
        for w in list where (w["kCGWindowOwnerName"] as? String) == "Dock" && ((w["kCGWindowLayer"] as? Int) ?? 0) > 0 {
            if let b = w["kCGWindowBounds"] as? [String: Any], let r = CGRect(dictionaryRepresentation: b as CFDictionary),
               r.width >= 800, r.height >= 500 { n += 1 }
        }
        return n >= 2
    }

    /// Topmost normal window under `p` (Accessibility coordinates), front to back.
    static func windowID(at p: CGPoint) -> WindowID? {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID),
              let list = (raw as NSArray) as? [[String: Any]] else { return nil }
        for w in list {
            guard (w["kCGWindowLayer"] as? Int) == 0,
                  let num = w["kCGWindowNumber"] as? Int,
                  let b = w["kCGWindowBounds"] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.contains(p) else { continue }
            return WindowID(num)
        }
        return nil
    }

    /// Park a window at the bottom-right corner of its monitor so only one pixel stays on screen.
    static func hide(_ el: AXUIElement, on monitor: Monitor) {
        var pos = CGPoint(x: monitor.frame.maxX - 1, y: monitor.frame.maxY - 1)
        if let pv = AXValueCreate(.cgPoint, &pos) { set(el, kAXPositionAttribute, pv) }
    }

    static func focus(_ w: AXWin) {
        _ = call(w.element) { AXUIElementPerformAction(w.element, kAXRaiseAction as CFString) }
        set(w.element, kAXMainAttribute, kCFBooleanTrue)
        set(w.element, kAXFocusedAttribute, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: w.pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    static func close(_ w: AXWin) {
        guard let btn: AXUIElement = attr(w.element, kAXCloseButtonAttribute) else { return }
        _ = call(btn) { AXUIElementPerformAction(btn, kAXPressAction as CFString) }
    }

    /// The window that currently has keyboard focus, if any.
    static func focusedWindowID() -> (id: WindowID, bundleID: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let w: AXUIElement = attr(ax, kAXFocusedWindowAttribute) else { return nil }
        var wid = CGWindowID(0)
        guard call(w, { _AXUIElementGetWindow(w, &wid) }) == .success, wid != 0 else { return nil }
        return (wid, app.bundleIdentifier ?? "?")
    }
}
