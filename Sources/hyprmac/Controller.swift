import AppKit
import HyprCore

final class Controller {
    private var config: Config
    private let engine: Engine
    private let hotkeys = HotkeyTap()
    private let border = BorderOverlay()
    private let launcher = Launcher()
    private var theme = Theme.all[0]
    private var known = [WindowID: AXWin]()
    private var applied = [WindowID: Placement]()
    private var retries = [WindowID: Int]()
    /// Where a window actually ended up after we placed it (apps clamp or snap to character cells).
    private var settled = [WindowID: CGRect]()
    private var observers = [pid_t: AXObserver]()
    private var tickQueued = false
    private var drag: Drag?
    /// Set when the scratchpad was toggled while empty: the next window of `scratchpadApp` is captured.
    private var pendingScratch: Date?

    private struct Drag {
        let id: WindowID
        let resize: Bool
        let floating: Bool
        let startCursor: CGPoint
        let startFrame: CGRect
        var lastCursor: CGPoint
        var lastApplied: CFTimeInterval = 0
    }
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var paused = false
    private var monitorsDirty = true
    private var lastWindowCount = -1
    private let myPid = ProcessInfo.processInfo.processIdentifier

    init() {
        let (cfg, _) = Config.load()
        config = cfg
        engine = Engine(monitors: Screens.monitors())
        applyConfig()
    }

    // MARK: - Lifecycle

    func start() {
        Log.write("start: trusted=\(Windows.isTrusted(prompt: false)) monitors=\(engine.monitors.count)")
        if !Windows.isTrusted(prompt: true) {
            notify("Allow hyprmac under System Settings > Privacy & Security > Accessibility, then start it again.")
        }
        setUpMenu()
        launcher.provider = { [weak self] in self?.launcherItems() ?? [] }
        launcher.onClose = { [weak self] in self?.focusEngineChoice() }
        hotkeys.handler = { [weak self] action in self?.handle(action) ?? false }
        hotkeys.mouseHandler = { [weak self] type, p, flags in self?.handleMouse(type, p, flags) ?? false }
        let tapOK = hotkeys.start()
        Log.write("key tap installed=\(tapOK) bindings=\(hotkeys.table.count)")
        if !tapOK {
            notify("Could not install the global key tap - is Accessibility (and Input Monitoring) allowed?")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.monitorsDirty = true }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func applyConfig() {
        engine.gap = config.gap
        engine.outerGap = config.outerGap
        let n = config.mainWorkspaces
        engine.preferredMonitor = { $0 <= n ? 0 : 1 }
        hotkeys.table = config.table()
        border.width = config.borderWidth
        border.inside = config.gap < config.borderWidth
        border.radius = config.borderRadius
        applyTheme()
    }

    private func reload() {
        let (cfg, problems) = Config.load()
        config = cfg
        applyConfig()
        monitorsDirty = true
        applied = [:]
        if !problems.isEmpty { notify(problems.joined(separator: "\n")) }
    }

    // MARK: - Accessibility notifications

    /// React to new windows, closed windows and focus changes immediately instead of waiting for
    /// the next timer tick (a new window would otherwise sit at the app's own position for a moment).
    private func observeApps() {
        var live = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != myPid && !app.isTerminated {
            live.insert(app.processIdentifier)
            observe(pid: app.processIdentifier)
        }
        for pid in Array(observers.keys) where !live.contains(pid) {
            if let o = observers[pid] { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .commonModes) }
            observers[pid] = nil
        }
    }

    private func observe(pid: pid_t) {
        guard observers[pid] == nil else { return }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon = refcon else { return }
            Unmanaged<Controller>.fromOpaque(refcon).takeUnretainedValue().requestTick()
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let obs = created else { return }
        let app = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(obs, app, note as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observers[pid] = obs
    }

    private func requestTick() {
        guard !tickQueued else { return }
        tickQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.tickQueued = false
            self?.tick()
        }
    }

    // MARK: - The loop

    private func tick() {
        if monitorsDirty {
            engine.setMonitors(Screens.monitors())
            monitorsDirty = false
            applied = [:]
        }
        if paused { border.hide(); updateStatus(); return }
        // Locked screen / screen saver: apps expose no windows, which would empty the layout.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"].contains(front) {
            border.hide()
            return
        }

        observeApps()

        // 1. reconcile the set of windows
        let current = Windows.list(excluding: myPid)
        var seen = Set<WindowID>()
        for w in current {
            seen.insert(w.id)
            if known[w.id] == nil {
                let float = !w.resizable || config.floatApps.contains(w.bundleID)
                engine.windowAppeared(w.id, floating: float, frame: float ? Windows.frame(of: w.element) : nil)
                if let t = pendingScratch {
                    if Date().timeIntervalSince(t) > 5 {
                        pendingScratch = nil
                    } else if NSRunningApplication(processIdentifier: w.pid)?.localizedName == config.scratchpadApp {
                        engine.moveToScratchpad(w.id, show: true)
                        pendingScratch = nil
                    }
                }
            }
            if Log.debug, known[w.id] == nil {
                Log.write("new win \(w.id) \(w.bundleID) resizable=\(w.resizable) float=\(engine.isFloating(w.id)) frame=\(Windows.frame(of: w.element).map { "\($0)" } ?? "?")")
            }
            known[w.id] = w
        }
        for id in Array(known.keys) where !seen.contains(id) {
            engine.windowGone(id)
            known[id] = nil
            applied[id] = nil
            retries[id] = nil
            settled[id] = nil
        }

        if current.count != lastWindowCount {
            Log.write("windows seen=\(current.count) trusted=\(Windows.isTrusted(prompt: false))")
            lastWindowCount = current.count
        }

        // 2. follow the focus the user set by clicking / app switching
        if let f = Windows.focusedWindowID(), known[f.id] != nil, f.id != engine.focused {
            engine.setFocused(f.id)
        }

        // 3. floating windows keep wherever the user put them
        for (id, w) in known where engine.isFloating(id) {
            if case .frame? = applied[id], let f = Windows.frame(of: w.element) { engine.noteFloatFrame(id, f) }
        }

        // 4. apply what changed
        applyPlan()
        updateBorder()
        updateStatus()
    }

    /// Outline the focused window, unless it is parked, fullscreen-native, or gone.
    private func updateBorder() {
        guard let id = engine.focused, let w = known[id] else { border.hide(); return }
        if case .hidden? = applied[id] { border.hide(); return }
        guard let f = Windows.frame(of: w.element) else { border.hide(); return }
        border.show(around: f)
    }

    private func applyPlan() {
        let plan = engine.plan()
        let monitors = engine.monitors
        for (id, placement) in plan {
            guard let w = known[id] else { continue }
            if let d = drag, d.id == id, !d.resize || d.floating { continue }   // the user is placing it by hand
            if applied[id] != placement {
                retries[id] = 0
            } else {
                // Same plan as before: only act when the app moved or resized the window itself
                // (a new window opening, an app restoring its own frame). Give up after a few tries
                // for apps whose minimum size cannot fit the tile.
                guard case .frame(let want) = placement, !engine.isFloating(id),
                      (retries[id] ?? 0) < 6,
                      let actual = Windows.frame(of: w.element), !Windows.framesMatch(actual, want) else { continue }
                // The app could not reach the tile and stayed where our last attempt left it: not an
                // intervention by the app, so do not fight it.
                if let s = settled[id], Windows.framesMatch(actual, s) { continue }
                retries[id] = (retries[id] ?? 0) + 1
            }
            if Log.debug {
                Log.write("place \(id) \(w.bundleID) want=\(placement) actual=\(Windows.frame(of: w.element).map { "\($0)" } ?? "?") retry=\(retries[id] ?? 0)")
            }
            switch placement {
            case .frame(let r): Windows.setFrame(w.element, r)
            case .hidden(let m): Windows.hide(w.element, on: monitors[min(m, monitors.count - 1)])
            }
            applied[id] = placement
            if case .frame = placement { settled[id] = Windows.frame(of: w.element) } else { settled[id] = nil }
        }
    }

    private func focusEngineChoice() {
        if let id = engine.focused, let w = known[id] { Windows.focus(w) }
    }

    // MARK: - Themes

    private static var themeFile: String {
        return NSString(string: "~/.config/hyprmac/theme").expandingTildeInPath
    }

    /// The theme picked at runtime (kept in ~/.config/hyprmac/theme) wins over the config file.
    private func applyTheme() {
        let saved = (try? String(contentsOfFile: Controller.themeFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        theme = saved.flatMap { Theme.named($0) } ?? Theme.named(config.theme) ?? Theme.all[0]
        border.color = NSColor(hex: config.borderColor ?? theme.accent) ?? .systemBlue
        launcher.theme = theme
    }

    private func setTheme(_ name: String) {
        guard let t = Theme.named(name) else { return }
        try? FileManager.default.createDirectory(atPath: (Controller.themeFile as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? t.name.write(toFile: Controller.themeFile, atomically: true, encoding: .utf8)
        applyTheme()
        Log.write("theme \(t.name)")
    }

    // MARK: - Launcher

    private func launcherItems() -> [LauncherItem] {
        var out = [LauncherItem]()
        for n in engine.workspaceNumbers {
            for id in engine.windows(in: n) {
                guard let w = known[id] else { continue }
                let app = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.bundleID
                let title = Windows.title(of: w.element) ?? ""
                out.append(LauncherItem(kind: .window, title: title.isEmpty ? app : "\(app) \u{2013} \(title)",
                                        detail: "window \u{00B7} workspace \(n)") { [weak self] in self?.menuSelect(id) })
            }
        }
        for id in engine.scratchpadWindows {
            guard let w = known[id] else { continue }
            let app = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.bundleID
            let title = Windows.title(of: w.element) ?? ""
            out.append(LauncherItem(kind: .window, title: title.isEmpty ? app : "\(app) \u{2013} \(title)",
                                    detail: "window \u{00B7} scratchpad") { [weak self] in self?.menuSelect(id) })
        }
        for app in Apps.installed() {
            out.append(LauncherItem(kind: .app, title: app.name, detail: "application") {
                NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
            })
        }
        func act(_ title: String, _ action: Action) {
            out.append(LauncherItem(kind: .action, title: title, detail: "action") { [weak self] in _ = self?.perform(action) })
        }
        act("Toggle scratchpad", .scratchpad)
        act("Send window to scratchpad", .moveToScratchpad)
        act("Toggle floating", .toggleFloat)
        act("Toggle fullscreen", .toggleFullscreen)
        act("Flip split", .toggleSplit)
        act("Close window", .close)
        act("Reload config", .reload)
        act("Pause / resume tiling", .togglePause)
        act("Next theme", .themeNext)
        for n in 1...9 {
            act("Go to workspace \(n)", .workspace(n))
            act("Move window to workspace \(n)", .moveToWorkspace(n))
        }
        for t in Theme.all { act("Theme: \(t.title)", .theme(t.name)) }
        return out
    }

    // MARK: - Mouse

    /// ⌘⌥ (configurable) + left drag moves, + right drag resizes. Returns true when the event is consumed.
    private func handleMouse(_ type: CGEventType, _ p: CGPoint, _ flags: CGEventFlags) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown:
            if Log.debug { Log.write("mouse down flags=\(Mods(flags: flags).rawValue) want=\(parseMods(config.mouseModifier)?.rawValue ?? -1) at \(p)") }
            drag = nil   // a stale drag (lost mouse-up) never survives a new click
            guard !paused, let mods = parseMods(config.mouseModifier), Mods(flags: flags) == mods else { return false }
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               config.passthroughApps.contains(front) { return false }
            let hit = Windows.windowID(at: p)
            if Log.debug { Log.write("mouse hit window=\(hit.map { String($0) } ?? "none") known=\(hit.map { known[$0] != nil } ?? false)") }
            guard let id = hit, let w = known[id], let frame = Windows.frame(of: w.element) else { return false }
            if case .hidden? = applied[id] { return false }
            engine.setFocused(id)
            Windows.focus(w)
            drag = Drag(id: id, resize: type == .rightMouseDown, floating: engine.isFloating(id),
                        startCursor: p, startFrame: frame, lastCursor: p)
            if Log.debug { Log.write("mouse \(type == .rightMouseDown ? "resize" : "move") \(id) floating=\(engine.isFloating(id))") }
            return true
        case .leftMouseDragged, .rightMouseDragged:
            guard var d = drag, let w = known[d.id] else { return drag != nil }
            if Log.debug { Log.write("mouse drag at \(p)") }
            let now = CACurrentMediaTime()
            guard now - d.lastApplied >= 0.016 else { return true }   // AX calls are slow; coalesce
            d.lastApplied = now
            if d.resize {
                if d.floating {
                    let size = CGSize(width: max(120, d.startFrame.width + p.x - d.startCursor.x),
                                      height: max(80, d.startFrame.height + p.y - d.startCursor.y))
                    Windows.setSize(w.element, size)
                } else {
                    engine.resizeBy(dx: p.x - d.lastCursor.x, dy: p.y - d.lastCursor.y)
                    applyPlan()
                }
            } else {
                Windows.setPosition(w.element, CGPoint(x: d.startFrame.minX + p.x - d.startCursor.x,
                                                       y: d.startFrame.minY + p.y - d.startCursor.y))
            }
            d.lastCursor = p
            drag = d
            updateBorder()
            return true
        case .leftMouseUp, .rightMouseUp:
            guard let d = drag else { return false }
            drag = nil
            if Log.debug { Log.write("mouse up at \(p)") }
            if let w = known[d.id] {
                if d.floating {
                    if let f = Windows.frame(of: w.element) {
                        engine.noteFloatFrame(d.id, f)
                        applied[d.id] = .frame(f)
                    }
                } else {
                    if !d.resize,
                       let target = engine.tiledFrames().first(where: { $0.key != d.id && $0.value.contains(p) })?.key {
                        engine.swapWindows(d.id, target)
                    }
                    applied[d.id] = nil
                    applyPlan()
                }
            }
            updateBorder()
            return true
        default:
            return false
        }
    }

    // MARK: - Hotkeys

    /// Returns true when the key was consumed.
    private func handle(_ action: Action) -> Bool {
        Log.write("hotkey \(action)")
        if case .togglePause = action { paused.toggle(); updateStatus(); return true }
        if paused { return false }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           config.passthroughApps.contains(front) {
            return false
        }
        if launcher.isVisible {
            // Only the launcher key itself works while it is open (it closes the panel).
            if case .launcher = action { launcher.hide(); return true }
            return false
        }
        return perform(action)
    }

    private func perform(_ action: Action) -> Bool {
        switch action {
        case .workspace(let n):
            engine.switchWorkspace(n)
            applyPlan()
            focusEngineChoice()
        case .moveToWorkspace(let n):
            engine.moveFocused(toWorkspace: n)
            applyPlan()
            focusEngineChoice()
        case .focus(let d):
            // No neighbour that way: hand the key back (e.g. ⌘← still moves the text cursor).
            guard engine.focus(d) else { return false }
            focusEngineChoice()
        case .swap(let d):
            engine.swap(d)
            applyPlan()
        case .resize(let d):
            engine.resize(d)
            applyPlan()
        case .toggleFloat:
            engine.toggleFloating()
            applyPlan()
        case .toggleFullscreen:
            engine.toggleFullscreen()
            applyPlan()
            focusEngineChoice()
        case .toggleSplit:
            engine.toggleSplit()
            applyPlan()
        case .close:
            if let id = engine.focused, let w = known[id] { Windows.close(w) }
        case .backAndForth:
            engine.backAndForth()
            applyPlan()
            focusEngineChoice()
        case .reload:
            reload()
        case .open(let app):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            // Terminal only gets a new window when it is handed a folder.
            p.arguments = app == "Terminal" ? ["-a", app, NSHomeDirectory()] : ["-a", app]
            try? p.run()
        case .scratchpad:
            if engine.toggleScratchpad() {
                applyPlan()
                focusEngineChoice()
            } else {
                pendingScratch = Date()
                return perform(.open(config.scratchpadApp))
            }
        case .moveToScratchpad:
            engine.moveFocusedToScratchpad()
            applyPlan()
            focusEngineChoice()
        case .launcher:
            launcher.show()
        case .theme(let name):
            setTheme(name)
        case .themeNext:
            setTheme(Theme.after(theme.name).name)
        case .togglePause:
            paused.toggle()
            updateStatus()
        }
        return true
    }

    // MARK: - Menu bar

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = MenuTarget.shared      // rebuilt every time it opens
        item.menu = menu
        statusItem = item
        MenuTarget.shared.controller = self
        rebuildMenu(menu)
    }

    /// Workspaces with their windows (click to jump there), then the fixed commands.
    fileprivate func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let target = MenuTarget.shared
        for n in engine.workspaceNumbers {
            let ids = engine.windows(in: n).filter { known[$0] != nil }
            if ids.isEmpty && n != engine.currentWorkspace { continue }
            let current = n == engine.currentWorkspace
            let head = NSMenuItem(title: "Workspace \(n)" + (current ? "  \u{2190} here" : ""), action: nil, keyEquivalent: "")
            head.isEnabled = false
            head.attributedTitle = NSAttributedString(string: head.title,
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            menu.addItem(head)
            if ids.isEmpty {
                let none = NSMenuItem(title: "no windows", action: nil, keyEquivalent: "")
                none.isEnabled = false
                none.indentationLevel = 1
                menu.addItem(none)
            }
            for id in ids {
                guard let w = known[id] else { continue }
                let app = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.bundleID
                let title = Windows.title(of: w.element) ?? ""
                var text = title.isEmpty ? app : "\(app) \u{2013} \(title)"
                if text.count > 60 { text = String(text.prefix(59)) + "\u{2026}" }
                let entry = NSMenuItem(title: text, action: #selector(MenuTarget.selectWindow(_:)), keyEquivalent: "")
                entry.target = target
                entry.representedObject = Int(id)
                entry.indentationLevel = 1
                if id == engine.focused { entry.state = .on }
                menu.addItem(entry)
            }
        }
        let pad = engine.scratchpadWindows.filter { known[$0] != nil }
        if !pad.isEmpty {
            let head = NSMenuItem(title: "Scratchpad", action: nil, keyEquivalent: "")
            head.isEnabled = false
            head.attributedTitle = NSAttributedString(string: head.title,
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            menu.addItem(head)
            for id in pad {
                guard let w = known[id] else { continue }
                let app = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.bundleID
                let title = Windows.title(of: w.element) ?? ""
                var text = title.isEmpty ? app : "\(app) \u{2013} \(title)"
                if text.count > 60 { text = String(text.prefix(59)) + "\u{2026}" }
                let entry = NSMenuItem(title: text, action: #selector(MenuTarget.selectWindow(_:)), keyEquivalent: "")
                entry.target = target
                entry.representedObject = Int(id)
                entry.indentationLevel = 1
                if id == engine.scratchShown { entry.state = .on }
                menu.addItem(entry)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Reload config", action: #selector(MenuTarget.reload), keyEquivalent: "").target = target
        menu.addItem(withTitle: "Pause / resume tiling", action: #selector(MenuTarget.pause), keyEquivalent: "").target = target
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit hyprmac", action: #selector(MenuTarget.quit), keyEquivalent: "q").target = target
    }

    fileprivate func menuSelect(_ id: WindowID) {
        guard known[id] != nil else { return }
        engine.activate(id)
        applyPlan()
        focusEngineChoice()
        updateBorder()
    }

    fileprivate func menuReload() { reload() }
    fileprivate func menuPause() { paused.toggle(); updateStatus() }

    private func updateStatus() {
        let title = paused ? "\u{25A6} \u{23F8}" : "\u{25A6} \(engine.currentWorkspace)"
        if statusItem?.button?.title != title { statusItem?.button?.title = title }
    }

    private func notify(_ text: String) {
        FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
        let alert = NSAlert()
        alert.messageText = "hyprmac"
        alert.informativeText = text
        alert.runModal()
    }
}

final class MenuTarget: NSObject, NSMenuDelegate {
    static let shared = MenuTarget()
    weak var controller: Controller?
    func menuNeedsUpdate(_ menu: NSMenu) { controller?.rebuildMenu(menu) }
    @objc func selectWindow(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? Int { controller?.menuSelect(WindowID(id)) }
    }
    @objc func reload() { controller?.menuReload() }
    @objc func pause() { controller?.menuPause() }
    @objc func quit() { NSApp.terminate(nil) }
}
