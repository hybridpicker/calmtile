import AppKit
import HyprCore

final class Controller {
    private var config: Config
    private let engine: Engine
    private let hotkeys = HotkeyTap()
    private let border = BorderOverlay()
    private var known = [WindowID: AXWin]()
    private var applied = [WindowID: Placement]()
    private var retries = [WindowID: Int]()
    /// Where a window actually ended up after we placed it (apps clamp or snap to character cells).
    private var settled = [WindowID: CGRect]()
    private var observers = [pid_t: AXObserver]()
    private var tickQueued = false
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
        hotkeys.handler = { [weak self] action in self?.handle(action) ?? false }
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
        border.radius = config.borderRadius
        border.color = NSColor(hex: config.borderColor) ?? .systemBlue
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

        observeApps()

        // 1. reconcile the set of windows
        let current = Windows.list(excluding: myPid)
        var seen = Set<WindowID>()
        for w in current {
            seen.insert(w.id)
            if known[w.id] == nil {
                let float = !w.resizable || config.floatApps.contains(w.bundleID)
                engine.windowAppeared(w.id, floating: float, frame: float ? Windows.frame(of: w.element) : nil)
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
        case .togglePause:
            break
        }
        return true
    }

    // MARK: - Menu bar

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "Reload config", action: #selector(MenuTarget.reload), keyEquivalent: "").target = MenuTarget.shared
        menu.addItem(withTitle: "Pause / resume tiling", action: #selector(MenuTarget.pause), keyEquivalent: "").target = MenuTarget.shared
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit hyprmac", action: #selector(MenuTarget.quit), keyEquivalent: "q").target = MenuTarget.shared
        item.menu = menu
        statusItem = item
        MenuTarget.shared.controller = self
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

final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    weak var controller: Controller?
    @objc func reload() { controller?.menuReload() }
    @objc func pause() { controller?.menuPause() }
    @objc func quit() { NSApp.terminate(nil) }
}
