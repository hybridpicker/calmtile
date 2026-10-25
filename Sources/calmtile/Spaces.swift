import AppKit
import IOKit
import CalmCore

// Private but long-stable read APIs of the window server (also used by yabai, AeroSpace-like tools).
// Switching the current Space works without special privileges on macOS 26; moving windows between
// Spaces does not (verified: CGSMoveWindowsToManagedSpace has no effect), so calmtile never tries.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ cid: Int32) -> UInt64
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("CGSManagedDisplaySetCurrentSpace") private func CGSManagedDisplaySetCurrentSpace(_ cid: Int32, _ display: CFString, _ space: UInt64)
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray?
@_silgen_name("CGSCopySpaces") private func CGSCopySpaces(_ cid: Int32, _ mask: Int32) -> CFArray?
// Live state of the system keyboard shortcuts in the window server (what System Settings > Keyboard writes to
// com.apple.symbolichotkeys); not persisted. AltTab uses the same pair to take Cmd+Tab from the system.
@_silgen_name("CGSSetSymbolicHotKeyEnabled") private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32
@_silgen_name("CGSIsSymbolicHotKeyEnabled") private func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

/// macOS desktops of the display that holds the active Space.
///
/// Workspace numbers stay with their desktops. macOS moves the most recently used desktops to the front whenever
/// Mission Control opens ("Automatically rearrange Spaces based on most recent use", on by default), so "the Nth
/// desktop" is a moving target: `⌘2` would land somewhere else after every swipe up. A desktop gets the lowest
/// free number when first seen (Dock order at the first start), kept in ~/.config/calmtile/desktops.json. With
/// that setting off the Dock's order is used as it is, like the system's own `⌃N` shortcuts.
enum Spaces {
    private static let cid = CGSMainConnectionID()

    private struct Layout {
        let display: String
        let spaces: [UInt64]   // normal desktops only, in the Dock's order (full-screen app Spaces are left out)
    }

    /// One reading of the desktops: every display's normal desktops, the display holding the active Space (a
    /// full-screen app Space counts for its display too), and the active Space.
    private struct Snapshot {
        let all: [Layout]
        let current: Layout?
        let active: UInt64
    }

    private static func read() -> Snapshot {
        Profile.ws(2)
        let active = CGSGetActiveSpace(cid)
        guard let raw = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return Snapshot(all: [], current: nil, active: active) }
        var out = [Layout]()
        var current: Layout?
        for d in raw {
            guard let id = d["Display Identifier"] as? String, let list = d["Spaces"] as? [[String: Any]] else { continue }
            let l = Layout(display: id, spaces: list.filter { ($0["type"] as? Int) == 0 }
                .compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value })
            out.append(l)
            if current == nil, list.contains(where: { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == active }) { current = l }
        }
        assign(out)
        return Snapshot(all: out, current: current ?? out.first, active: active)
    }

    /// Within a tick the desktops are read once (`beginTick` ... `endTick`); every query asked several times per
    /// window used to read them twice per call. Outside a tick (hotkeys, the steps of a switch) they are read live.
    private static var cached: Snapshot?
    private static var windowNumbers = [WindowID: Int?]()
    private static var caching = false

    static func beginTick() {
        caching = true
        cached = nil
        windowNumbers.removeAll(keepingCapacity: true)
    }

    static func endTick() {
        caching = false
        cached = nil
        windowNumbers.removeAll(keepingCapacity: true)
    }

    private static func snapshot() -> Snapshot {
        if caching, let s = cached { return s }
        let s = read()
        if caching { cached = s }
        return s
    }

    private static func layouts() -> [Layout] { return snapshot().all }

    private static func layout() -> Layout? { return snapshot().current }

    // MARK: Numbering

    /// "Automatically rearrange Spaces based on most recent use" (System Settings > Desktop & Dock); on when unset.
    static let stableNumbering: Bool = {
        let v = CFPreferencesCopyAppValue("mru-spaces" as CFString, "com.apple.dock" as CFString)
        return (v as? NSNumber)?.boolValue ?? true
    }()

    private static let numbersFile = NSString(string: "~/.config/calmtile/desktops.json").expandingTildeInPath
    private static var numbers: [UInt64: Int] = {
        guard let data = FileManager.default.contents(atPath: numbersFile),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Int] else { return [:] }
        var out = [UInt64: Int]()
        for (k, v) in obj { if let id = UInt64(k) { out[id] = v } }
        return out
    }()
    /// Number for the next desktop that appears (the one `⌘N` is creating).
    private static var reserved: Int?
    /// The one-shot test aids only read the numbers; the running instance owns the file.
    static var readOnlyNumbers = false

    private static func saveNumbers() {
        guard !readOnlyNumbers else { return }
        let obj = Dictionary(uniqueKeysWithValues: numbers.map { (String($0.key), $0.value) })
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(atPath: (numbersFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: numbersFile), options: .atomic)
    }

    /// Number every new desktop (lowest free number on its display, or the reserved one) and forget removed ones.
    private static func assign(_ all: [Layout]) {
        guard stableNumbering else { return }
        var changed = false
        for l in all {
            var used = Set(l.spaces.compactMap { numbers[$0] })
            for s in l.spaces where numbers[s] == nil {
                var n = 1
                if let r = reserved, !used.contains(r) { n = r; reserved = nil } else { while used.contains(n) { n += 1 } }
                numbers[s] = n
                used.insert(n)
                changed = true
            }
        }
        let living = Set(all.flatMap { $0.spaces })
        for id in numbers.keys where !living.contains(id) {
            numbers[id] = nil
            changed = true
        }
        if changed { saveNumbers() }
    }

    private static func number(of space: UInt64, in l: Layout) -> Int? {
        if !stableNumbering { return l.spaces.firstIndex(of: space).map { $0 + 1 } }
        return l.spaces.contains(space) ? numbers[space] : nil
    }

    private static func space(number n: Int, in l: Layout) -> UInt64? {
        if !stableNumbering { return n >= 1 && n <= l.spaces.count ? l.spaces[n - 1] : nil }
        return l.spaces.first { numbers[$0] == n }
    }

    // MARK: Queries and switching

    static func exists(_ n: Int) -> Bool {
        guard let l = layout() else { return false }
        return space(number: n, in: l) != nil
    }

    /// Position of workspace `n` in the Dock's current order (what the system's `⌃<digit>` shortcuts count).
    static func position(of n: Int) -> Int? {
        guard let l = layout(), let id = space(number: n, in: l), let i = l.spaces.firstIndex(of: id) else { return nil }
        return i + 1
    }

    /// Workspace number of the active Space, nil when a full-screen app Space is active.
    static func activeNumber() -> Int? {
        let s = snapshot()
        guard let l = s.current else { return nil }
        return number(of: s.active, in: l)
    }

    /// Desktops the window server currently shows ("current" set). After a switch it must hold exactly one per
    /// display; two mean the desktop just left is still being drawn.
    static func shownSpaces() -> [UInt64] {
        Profile.ws()
        return (CGSCopySpaces(cid, 5) as? [NSNumber])?.map { $0.uint64Value } ?? []
    }

    /// Key codes of the digit keys (ANSI), as the system shortcuts "Switch to Desktop N" use them.
    static let digitKeyCodes: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25]
    /// Tag on key events calmtile synthesizes, so its own key tap lets them pass whatever the bindings say.
    static let ownEventTag: Int64 = 0x4361_6C54   // "CalT"

    /// Down and up like a real press: the hotkey consumes the key-down, the key-up still reaches the frontmost app.
    /// Right after a desktop switch that app may be the one just left, and a key event delivered to an app whose
    /// windows are on another desktop makes macOS switch back there about a second later (seen on macOS 26.5). A
    /// human release comes 100 ms or more after the press, by which time the Dock has activated an app of the new
    /// desktop; the synthetic one keeps that distance.
    static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: ownEventTag)
            e?.post(tap: .cghidEventTap)
            usleep(down ? 120_000 : 10_000)
        }
    }

    /// Press the system shortcut "Switch to Desktop <position>" (Control+digit) for the Dock, enabling it in the
    /// window server for just that moment when the user has it off in System Settings (the usual state; nothing is
    /// written to the preferences and the user's own Control+digit keeps its meaning). `completion` runs once the
    /// shortcut is back in its previous state.
    static func pressDesktopShortcut(position: Int, restoreAfter: TimeInterval = 0.4, completion: (() -> Void)? = nil) -> Bool {
        guard position >= 1, position <= 9, let key = digitKeyCodes[position] else { return false }
        let hotKey = Int32(117 + position)
        let was = CGSIsSymbolicHotKeyEnabled(hotKey)
        if !was { CGSSetSymbolicHotKeyEnabled(hotKey, true) }
        postKey(key, flags: .maskControl)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
            if !was { CGSSetSymbolicHotKeyEnabled(hotKey, false) }
            completion?()
        }
        return true
    }

    /// Switch to workspace `n` the way the Dock does: through its own "Switch to Desktop" shortcut.
    ///
    /// Setting the display's current Space directly (CGSManagedDisplaySetCurrentSpace) is accepted from any process
    /// but only half of the job: the new desktop becomes current while the one just left stays shown, so the window
    /// server draws both (its "current" set then lists two Spaces) and the windows of the old desktop remain on
    /// screen, overlapping the new ones. Hiding the old one (CGSHideSpaces) is honoured for the Dock alone, verified
    /// on macOS 26.5. The Dock's shortcut does the whole transition. Beyond position 9 the direct call remains.
    @discardableResult
    static func switchTo(_ n: Int) -> Bool {
        guard let l = layout(), let id = space(number: n, in: l), let i = l.spaces.firstIndex(of: id) else { return false }
        if CGSGetActiveSpace(cid) == id { return true }
        if pressDesktopShortcut(position: i + 1) { return true }
        CGSManagedDisplaySetCurrentSpace(cid, l.display as CFString, id)
        return true
    }

    /// Workspace number a window lives on, straight from the window server (nil: not on any desktop, such as a
    /// window its app has ordered out, a full-screen Space, or another display). A window shown on every desktop
    /// counts as the active one's. Unlike the Accessibility window list, which still shows the desktop just left
    /// for a moment after a switch, this is current at once.
    static func number(ofWindow id: WindowID) -> Int? {
        if caching, let n = windowNumbers[id] { return n }
        let s = snapshot()
        var n: Int?
        // The call takes a list but answers with the union of their Spaces, so it is asked one window at a time.
        Profile.ws()
        if let l = s.current, let out = CGSCopySpacesForWindows(cid, 7, [NSNumber(value: id)] as CFArray) as? [NSNumber] {
            let ids = out.map { $0.uint64Value }
            if ids.contains(s.active) { n = number(of: s.active, in: l) }
            else if ids.count == 1, let space = ids.first { n = number(of: space, in: l) }
        }
        if caching { windowNumbers[id] = n }
        return n
    }

    /// Every normal window that exists, on any Space (the Accessibility list only shows the current one), with
    /// whether the window server draws it right now (false: minimized, its app hidden, or ordered out).
    static func existingWindows() -> [WindowID: Bool] {
        Profile.ws()
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID),
              let list = (raw as NSArray) as? [[String: Any]] else { return [:] }
        var out = [WindowID: Bool]()
        for w in list where (w["kCGWindowLayer"] as? Int) == 0 {
            if let n = w["kCGWindowNumber"] as? Int { out[WindowID(n)] = (w["kCGWindowIsOnscreen"] as? Bool) ?? false }
        }
        return out
    }
}

@_silgen_name("CoreDockSendNotification") private func CoreDockSendNotification(_ name: CFString, _ unknown: UnsafeMutableRawPointer?)

// MARK: - Desktops on demand

/// Creating a desktop has no API short of disabling SIP. Mission Control's Spaces bar is scriptable through
/// Accessibility, though (the Dock exposes it with stable identifiers, locale-independent: `mc.spaces.add`,
/// `mc.spaces.list`); yabai does the same. So `⌘N` on a missing desktop opens Mission Control for about a second,
/// presses "add desktop" and clicks the new desktop, which also closes the overview.
extension Spaces {
    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &ref) == .success else { return nil }
        return ref as? T
    }

    /// Toggle Mission Control the way the Dock itself does (no system shortcut needed).
    static func toggleMissionControl() {
        CoreDockSendNotification("com.apple.expose.awake" as CFString, nil)
    }

    private static func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let ax = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1.0)
        return ax
    }

    /// Depth-first search by accessibility identifier, `within` an element (the Dock, or one display's group).
    private static func find(_ id: String, within el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if (attr(el, kAXIdentifierAttribute) as String?) == id { return el }
        guard depth < 6, let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return nil }
        for k in kids {
            // Elements do not inherit the Dock element's timeout; Mission Control may answer slowly while it opens.
            AXUIElementSetMessagingTimeout(k, 1.0)
            if let hit = find(id, within: k, depth: depth + 1) { return hit }
        }
        return nil
    }

    /// Mission Control's group for the display that holds the active Space (`mc.display`, one per display). With
    /// several displays the one whose frame lies on that display is taken; the first one when that cannot be told.
    private static func displayGroup(in dock: AXUIElement) -> AXUIElement? {
        guard let mc = find("mc", within: dock), let kids: [AXUIElement] = attr(mc, kAXChildrenAttribute) else { return nil }
        for k in kids { AXUIElementSetMessagingTimeout(k, 1.0) }
        let groups = kids.filter { (attr($0, kAXIdentifierAttribute) as String?) == "mc.display" }
        if groups.count <= 1 { return groups.first }
        guard let want = layout()?.display, let screen = NSScreen.screens.first(where: { uuid(of: $0) == want }),
              let mainHeight = NSScreen.screens.first?.frame.height else { return groups.first }
        let f = screen.frame
        let axFrame = CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
        for g in groups {
            guard let v: AXValue = attr(g, kAXPositionAttribute) else { continue }
            var p = CGPoint.zero
            if AXValueGetValue(v, .cgPoint, &p), axFrame.contains(p) { return g }
        }
        return groups.first
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let u = CGDisplayCreateUUIDFromDisplayID(n.uint32Value) else { return nil }
        return CFUUIDCreateString(nil, u.takeRetainedValue()) as String
    }

    /// The desktop buttons of the Spaces bar, left to right (press = switch there and leave Mission Control).
    private static func desktopButtons(in group: AXUIElement) -> [AXUIElement] {
        guard let list = find("mc.spaces.list", within: group), let kids: [AXUIElement] = attr(list, kAXChildrenAttribute) else { return [] }
        for k in kids { AXUIElementSetMessagingTimeout(k, 1.0) }
        return kids
    }

    private static func poll(every interval: TimeInterval, attempts: Int, until cond: @escaping () -> Bool, then: @escaping (Bool) -> Void) {
        if cond() { then(true); return }
        guard attempts > 0 else { then(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { poll(every: interval, attempts: attempts - 1, until: cond, then: then) }
    }

    /// Create workspace `n` as a new desktop and switch there through Mission Control. With stable numbering only
    /// `n` is created, as in Hyprland, and takes the number `n` whatever its position; with the Dock's order,
    /// desktops are added until position `n` exists. `completion` runs on the main thread; false when the Dock did
    /// not show its Spaces bar in time (nothing is left open then).
    static func createAndSwitch(to n: Int, completion: @escaping (Bool) -> Void) {
        guard n >= 1, n <= 16, let before = layout(), before.spaces.count < 16, let dock = dockElement() else { completion(false); return }
        let known = Set(before.spaces)
        let wanted = stableNumbering ? before.spaces.count + 1 : n
        let opened = !Windows.overviewOpen()
        if opened { toggleMissionControl() }
        func bail() {
            reserved = nil
            if opened, Windows.overviewOpen() { toggleMissionControl() }
            completion(false)
        }
        poll(every: 0.1, attempts: 20, until: { displayGroup(in: dock).flatMap { find("mc.spaces.add", within: $0) } != nil }) { ready in
            guard ready, let group = displayGroup(in: dock) else { bail(); return }
            reserved = n
            func switchToNew() {
                reserved = nil
                guard let now = layout(),
                      let id = stableNumbering ? now.spaces.first(where: { !known.contains($0) }) : now.spaces.dropFirst(n - 1).first else { bail(); return }
                if stableNumbering, numbers[id] != n { numbers[id] = n; saveNumbers() }   // another display's assignment ran first
                // Click the new desktop (switches with the usual animation and closes the overview). The Dock ignores
                // the click while the overview is still animating in, so give it a moment; the Dock may also have
                // reordered the bar by now, so look the button up by the desktop's current position.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let buttons = desktopButtons(in: group)
                    if let i = layout()?.spaces.firstIndex(of: id), i < buttons.count {
                        AXUIElementPerformAction(buttons[i], kAXPressAction as CFString)
                    }
                    poll(every: 0.1, attempts: 10, until: { CGSGetActiveSpace(cid) == id }) { switched in
                        if switched { completion(true); return }
                        // Plan B: leave the overview ourselves and switch the way `⌘N` always does.
                        Log.write("Mission Control did not switch to desktop \(n): closing it and switching directly")
                        if Windows.overviewOpen() { toggleMissionControl() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { completion(switchTo(n)) }
                    }
                }
            }
            func addOne() {
                let have = layout()?.spaces.count ?? 0
                if have >= wanted { switchToNew(); return }
                guard let add = find("mc.spaces.add", within: group),
                      AXUIElementPerformAction(add, kAXPressAction as CFString) == .success else { bail(); return }
                poll(every: 0.1, attempts: 15, until: { (layout()?.spaces.count ?? 0) > have }) { ok in
                    if ok { addOne() } else { bail() }
                }
            }
            addOne()
        }
    }

    /// Remove workspace `n` through its Mission Control button (macOS moves its windows to another desktop).
    /// Test aid; the Dock's own order is looked up after the overview is open, since it may have changed by then.
    static func removeDesktop(_ n: Int, completion: @escaping (Bool) -> Void) {
        guard let l = layout(), let id = space(number: n, in: l), l.spaces.count > 1, let dock = dockElement() else { completion(false); return }
        let opened = !Windows.overviewOpen()
        if opened { toggleMissionControl() }
        poll(every: 0.1, attempts: 20, until: { displayGroup(in: dock).flatMap { find("mc.spaces.list", within: $0) } != nil }) { ready in
            func finish(_ ok: Bool) {
                if opened, Windows.overviewOpen() { toggleMissionControl() }
                completion(ok)
            }
            // Like the click on a desktop, the removal is ignored while the overview is still animating in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard ready, let group = displayGroup(in: dock), let i = layout()?.spaces.firstIndex(of: id) else {
                    Log.write("remove desktop \(n): Spaces bar not found (ready=\(ready))")
                    finish(false)
                    return
                }
                let buttons = desktopButtons(in: group)
                guard i < buttons.count else { Log.write("remove desktop \(n): position \(i + 1) but only \(buttons.count) buttons"); finish(false); return }
                let err = AXUIElementPerformAction(buttons[i], "AXRemoveDesktop" as CFString)
                guard err == .success else { Log.write("remove desktop \(n): AXRemoveDesktop failed (\(err.rawValue))"); finish(false); return }
                poll(every: 0.1, attempts: 20, until: { !(layout()?.spaces.contains(id) ?? true) }) { removed in
                    if !removed { Log.write("remove desktop \(n): the Dock accepted the action but the desktop is still there") }
                    finish(removed)
                }
            }
        }
    }

    /// Roles, identifiers and actions of the Dock's accessibility tree with Mission Control open (test aid).
    /// Descriptions are printed for the Spaces bar only: the window thumbnails carry window titles.
    static func dumpDock(depth maxDepth: Int) -> String {
        var lines = ["trusted=\(AXIsProcessTrusted())"]
        func walk(_ el: AXUIElement, _ depth: Int, _ inSpaces: Bool) {
            let role: String = attr(el, kAXRoleAttribute) ?? "?"
            let sub: String = attr(el, kAXSubroleAttribute) ?? ""
            let ident: String = attr(el, kAXIdentifierAttribute) ?? ""
            let spaces = inSpaces || ident == "mc.spaces"
            let desc: String = spaces ? (attr(el, kAXDescriptionAttribute) ?? "") : ""
            var names: CFArray?
            AXUIElementCopyActionNames(el, &names)
            lines.append(String(repeating: "  ", count: depth) + "\(role) \(sub) id=\(ident) desc=\(desc) actions=\((names as? [String]) ?? [])")
            guard depth < maxDepth, let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return }
            for k in kids { walk(k, depth + 1, spaces) }
        }
        guard let dock = dockElement() else { return "Dock not running" }
        let opened = !Windows.overviewOpen()
        if opened { toggleMissionControl() }
        usleep(600_000)
        walk(dock, 0, false)
        if opened { toggleMissionControl() }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Secure keyboard entry

extension Spaces {
    /// While an app holds Secure Keyboard Entry (Terminal's menu item, a password field, a password manager), the
    /// window server delivers keys to no event tap at all: no hotkey works until it ends. Returns the pid holding
    /// it (nil when off or unknown).
    static func secureInputPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [[String: Any]] else { return nil }
        for u in users {
            if let p = u["kCGSSessionSecureInputPID"] as? NSNumber { return pid_t(p.int32Value) }
        }
        return nil
    }
}
