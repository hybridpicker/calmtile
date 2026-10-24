import AppKit

if CommandLine.arguments.contains("--print-config") {
    print(Config.load().0.json())
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
        let ax = Windows.list(excluding: getpid()).map { "\($0.bundleID.split(separator: ".").last.map(String.init) ?? "?")@\(Spaces.number(ofWindow: $0.id).map(String.init) ?? "-")" }
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
