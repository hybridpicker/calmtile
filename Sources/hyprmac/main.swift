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
   let combo = parseCombo(CommandLine.arguments[i + 1]) {   // test aid: synthesize a key press for the running instance
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
