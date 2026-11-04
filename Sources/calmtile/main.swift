import AppKit

if CommandLine.arguments.contains("--print-config") {
    let (cfg, problems) = Config.load()
    print(cfg.json())
    for p in problems { FileHandle.standardError.write("config: \(p)\n".data(using: .utf8)!) }
    exit(0)
}

if CommandLine.arguments.contains("--dump-windows") {
    print(Windows.dump())
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--dump-dock") {   // test aid: the Dock's accessibility tree while Mission Control is open
    let depth = i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) ?? 6 : 6
    print(Spaces.dumpDock(depth: depth))
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--remove-desktop"), i + 1 < CommandLine.arguments.count,
   let n = Int(CommandLine.arguments[i + 1]) {   // test aid: undo a desktop created by `--post-key cmd-N`
    Spaces.readOnlyNumbers = true
    Spaces.removeDesktop(n) { ok in print(ok ? "removed desktop \(n)" : "could not remove desktop \(n)"); exit(ok ? 0 : 1) }
    RunLoop.main.run()
}

if let i = CommandLine.arguments.firstIndex(of: "--probe-switch"), i + 1 < CommandLine.arguments.count,
   let n = Int(CommandLine.arguments[i + 1]) {   // test aid: how long the Accessibility window list lags a desktop switch
    Spaces.readOnlyNumbers = true
    let before = Spaces.activeNumber()
    let t0 = Date()
    func sample() -> String {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        let ax = Windows.list(excluding: getpid()).windows.map { "\($0.bundleID.split(separator: ".").last.map(String.init) ?? "?")@\(Spaces.number(ofWindow: $0.id).map(String.init) ?? "-")" }
        let drawn = Spaces.existingWindows().filter { $0.value }.keys.compactMap { Spaces.number(ofWindow: $0) }
        return "\(ms) ms: active=\(Spaces.activeNumber().map(String.init) ?? "?") ax=\(ax.sorted()) onscreen=\(Set(drawn).sorted())"
    }
    print(sample())
    print(Spaces.switchTo(n) ? "switched to \(n)" : "no desktop \(n)")
    for _ in 0..<16 { usleep(50_000); print(sample()) }
    if let b = before { Spaces.switchTo(b) }
    usleep(800_000)
    print(sample())
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--probe-hotkey-switch"), i + 1 < CommandLine.arguments.count,
   let n = Int(CommandLine.arguments[i + 1]) {   // test aid: switch to workspace n through the Dock's shortcut and report the window server's state
    Spaces.readOnlyNumbers = true
    func state(_ label: String) { print("\(label): active=\(Spaces.activeNumber().map(String.init) ?? "?") shown=\(Spaces.shownSpaces())") }
    // --delay <seconds>: wait before switching, so the launch of this helper itself (LaunchServices activates and
    // deactivates apps around it) is kept apart from the switch. --restore-after <seconds>: when the shortcut is
    // switched back off (default 0.4 s as in normal use).
    func arg(_ name: String) -> Double? {
        guard let j = CommandLine.arguments.firstIndex(of: name), j + 1 < CommandLine.arguments.count else { return nil }
        return Double(CommandLine.arguments[j + 1])
    }
    func front() -> String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.split(separator: ".").last.map(String.init) ?? "?" }
    if let d = arg("--delay") { RunLoop.main.run(until: Date().addingTimeInterval(d)) }
    state("before (front=\(front()))")
    let t0 = Date()
    let restore: TimeInterval = arg("--restore-after") ?? 0.4
    if let pos = Spaces.position(of: n) {
        print("asked for workspace \(n) (position \(pos)), shortcut restored after \(restore) s: \(Spaces.pressDesktopShortcut(position: pos, restoreAfter: restore) { print("  shortcut restored") })")
    } else { print("no desktop \(n)") }
    var last = ""
    for _ in 0..<45 {   // the shortcut is switched back on the main queue, so run the loop while sampling
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let now = "active=\(Spaces.activeNumber().map(String.init) ?? "?") shown=\(Spaces.shownSpaces()) front=\(front())"
        if now != last { print("\(Int(Date().timeIntervalSince(t0) * 1000)) ms: \(now)"); last = now }
    }
    exit(0)
}

if CommandLine.arguments.contains("--restore-spotlight") {
    SpotlightMode.restore()
    exit(0)
}

if CommandLine.arguments.contains("--apply-spotlight") {   // manual test of the apps-only switch
    SpotlightMode.enableAppsOnly()
    exit(0)
}

if CommandLine.arguments.contains("--install-login") { LoginItem.install(); exit(0) }
if CommandLine.arguments.contains("--uninstall-login") { LoginItem.uninstall(); exit(0) }

if let i = CommandLine.arguments.firstIndex(of: "--post-drag"), i + 4 < CommandLine.arguments.count {
    // test aid: a left-button drag from (x0, y0) to (x1, y1) in global coordinates (title-bar drag of a window). Events
    // only reach the window server from a process with the Accessibility grant, which a shell's tools lack.
    let v = CommandLine.arguments[(i + 1)...(i + 4)].compactMap { Double($0) }
    guard v.count == 4 else { print("--post-drag x0 y0 x1 y1"); exit(1) }
    let src = CGEventSource(stateID: .hidSystemState)
    func post(_ t: CGEventType, _ x: Double, _ y: Double) {
        let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
        if t != .mouseMoved { e?.setIntegerValueField(.mouseEventClickState, value: 1) }
        e?.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, v[0], v[1]); usleep(100_000)
    post(.leftMouseDown, v[0], v[1]); usleep(200_000)
    for k in 1...30 {
        let f = Double(k) / 30
        post(.leftMouseDragged, v[0] + (v[2] - v[0]) * f, v[1] + (v[3] - v[1]) * f); usleep(20_000)
    }
    usleep(200_000)
    post(.leftMouseUp, v[2], v[3])
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--post-key"), i + 1 < CommandLine.arguments.count,
   let combo = parseCombo(CommandLine.arguments[i + 1])
    ?? keyCodes[CommandLine.arguments[i + 1].lowercased()].map({ KeyCombo(keyCode: $0, mods: []) }) {   // test aid: synthesize a key press (bare keys allowed here, e.g. escape)
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(combo.keyCode), keyDown: down)
        var f = CGEventFlags()
        if combo.mods.contains(.cmd) { f.insert(.maskCommand) }
        if combo.mods.contains(.alt) { f.insert(.maskAlternate) }
        if combo.mods.contains(.ctrl) { f.insert(.maskControl) }
        if combo.mods.contains(.shift) { f.insert(.maskShift) }
        e?.flags = f
        e?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
let controller = Controller()
controller.start()
app.run()
