import AppKit
import Carbon
import CalmCore

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
    private var overview = false
    private var overviewTimer: Timer?
    private var drag: Drag?
    /// A tiled window the user is dragging by its title bar (not with the mouse modifier).
    private var nativeDrag: WindowID?
    /// Set when the scratchpad was toggled while empty: the next window of `scratchpadApp` is captured.
    private var pendingScratch: Date?
    /// Mission Control is being driven to create a desktop: ticks and further workspace keys wait.
    private var creatingDesktop = false
    /// Secure Keyboard Entry is on somewhere: no hotkey can arrive (shown in the menu bar, logged once).
    private var secureInput = false
    /// Window the outline was last flashed for; with `borderFlash` it hides itself after that time.
    private var borderShownFor: WindowID?
    private var borderTimer: Timer?
    /// When the current desktop last changed (desktops mode): the Accessibility window list lags behind for a moment.
    private var switchedAt = Date.distantPast
    /// Desktop a window was last reported on by the window server; a window is re-homed only when two ticks agree
    /// and no desktop transition is being drawn, since the report wobbles while the Dock animates a switch.
    private var reportedDesktop = [WindowID: Int]()

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
    /// Menu toggle for this run; starts from `spotlightAppsOnly` and follows it on reload.
    private var spotlightOn = false
    private var monitorsDirty = true
    private var lastWindowCount = -1
    private let myPid = ProcessInfo.processInfo.processIdentifier

    init() {
        let (cfg, _) = Config.load()
        config = cfg
        spotlightOn = cfg.spotlightAppsOnly
        engine = Engine(monitors: Screens.monitors())
        applyConfig()
    }

    // MARK: - Lifecycle

    func start() {
        Windows.setDefaultTimeout()
        Log.write("start: trusted=\(Windows.isTrusted(prompt: false)) monitors=\(engine.monitors.count)")
        if !Windows.isTrusted(prompt: true) {
            notify("Allow calmtile under System Settings > Privacy & Security > Accessibility, then start it again.")
        }
        setUpMenu()
        updateSpotlight()
        installTerminationHandlers()
        launcher.provider = { [weak self] in self?.launcherItems() ?? [] }
        launcher.onClose = { [weak self] in self?.focusEngineChoice() }
        hotkeys.handler = { [weak self] action, late in self?.handle(action, late: late) ?? false }
        hotkeys.mouseHandler = { [weak self] type, p, flags in self?.handleMouse(type, p, flags) ?? false }
        let tapOK = hotkeys.start()
        Log.write("key tap installed=\(tapOK) bindings=\(hotkeys.table.count)")
        if !tapOK {
            notify("Could not install the global key tap - is Accessibility (and Input Monitoring) allowed?")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.monitorsDirty = true }
        // A desktop switch (ours, a swipe, Mission Control): the outline belongs to the desktop just left, so it goes
        // at once instead of lingering until the next tick; the newly focused window flashes afterwards.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.hideBorder()
            self?.requestTick()
        }
        // Mission Control opens within a fraction of a second: poll for it faster than the main tick.
        let ot = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.checkOverview() }
        RunLoop.main.add(ot, forMode: .common)
        overviewTimer = ot
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func applyConfig() {
        engine.gap = config.gap
        engine.outerGap = config.outerGap
        engine.minTile = CGSize(width: config.minTileWidth, height: config.minTileHeight)
        let n = config.mainWorkspaces
        engine.preferredMonitor = config.useSpaces ? { _ in 0 } : { $0 <= n ? 0 : 1 }
        engine.allowOverflow = !config.useSpaces
        hotkeys.table = config.table()
        hotkeys.mouseModifier = parseMods(config.mouseModifier)
        border.width = config.borderWidth
        border.inside = config.gap < config.borderWidth
        border.radius = config.borderRadius
        applyTheme()
    }

    private func reload() {
        let (cfg, problems) = Config.load()
        config = cfg
        applyConfig()
        spotlightOn = config.spotlightAppsOnly
        updateSpotlight()
        monitorsDirty = true
        applied = [:]
        if !problems.isEmpty { notify(problems.joined(separator: "\n")) }
    }

    // MARK: - Accessibility notifications

    /// React to new windows, closed windows and focus changes immediately instead of waiting for
    /// the next timer tick (a new window would otherwise sit at the app's own position for a moment).
    private func observeApps() {
        var live = Set<pid_t>()
        for app in Windows.regularApps() where app.processIdentifier != myPid {
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
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let me = Unmanaged<Controller>.fromOpaque(refcon).takeUnretainedValue()
            if Profile.on {
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                Profile.note((notification as String).replacingOccurrences(of: "AX", with: ""),
                             NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?")
            }
            if notification as String == kAXWindowCreatedNotification { me.windowCreated(element) }
            me.requestTick()
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let obs = created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let me = Unmanaged.passUnretained(self).toOpaque()
        timed("observing \(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? String(pid))") {
            for note in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification] {
                AXObserverAddNotification(obs, app, note as CFString, me)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observers[pid] = obs
    }

    /// A window was just created: tile it now, while it is still appearing, instead of on the next tick (a few
    /// hundred milliseconds later, when it had already been drawn at the app's own size and visibly jumped).
    /// The tick afterwards finds it known and only confirms the placement.
    private func windowCreated(_ element: AXUIElement) {
        guard !paused, !overview, !creatingDesktop, let w = Windows.standardWindow(element, ignoring: config.ignoreApps),
              known[w.id] == nil else { return }
        let desktop: Int? = config.useSpaces ? (Spaces.number(ofWindow: w.id) ?? engine.currentWorkspace) : nil
        let float = !w.resizable || config.floatApps.contains(w.bundleID) || titleFloats(w)
        engine.windowAppeared(w.id, floating: float, frame: float ? Windows.frame(of: w.element) : nil, workspace: desktop)
        known[w.id] = w
        if Log.debug { Log.write("created win \(w.id) \(w.bundleID) float=\(float): placed at once") }
        applyPlan()
    }

    /// While Mission Control is open every window sits at its layout position (not parked in a corner), so
    /// macOS shows a proper overview. On leaving it, the workspace of the window you picked becomes current.
    private func checkOverview() {
        guard !paused, !config.useSpaces else { return }
        let open = Windows.overviewOpen()
        if open == overview { return }
        overview = open
        if open {
            hideBorder()
            for (id, f) in engine.overviewPlan() {
                guard let w = known[id], case .hidden? = applied[id] else { continue }
                Windows.setFrame(w.element, f)
            }
            Log.write("overview opened")
        } else {
            if let f = Windows.focusedWindowID(), known[f.id] != nil,
               let n = engine.workspaceOf(f.id), n != 0, n != engine.currentWorkspace {
                engine.activate(f.id)
            }
            applied = [:]
            Log.write("overview closed")
            tick()
        }
    }

    private func requestTick() {
        Profile.tickRequested()
        guard !tickQueued else { return }
        tickQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.tickQueued = false
            self?.tick()
        }
    }

    // MARK: - The loop

    /// Run `work` and log it when it took long: a step that blocks the main thread holds up every hotkey
    /// (the key is kept, but the action runs late) and every placement.
    @discardableResult
    private func timed<T>(_ what: @autoclosure () -> String, limit: TimeInterval = 0.5, _ work: () -> T) -> T {
        let t0 = CACurrentMediaTime()
        let r = work()
        let dt = CACurrentMediaTime() - t0
        if dt > limit { Log.write("slow: \(what()) took \(String(format: "%.1f", dt)) s") }
        return r
    }

    private func tick() {
        Profile.beginTick()
        // The usable area also changes when the menu bar or Dock hide/show setting is switched, which
        // sends no notification, so compare on every tick (cheap) instead of waiting for an event.
        let monitors = Screens.monitors()
        if monitorsDirty || monitors != engine.monitors {
            engine.setMonitors(monitors)
            monitorsDirty = false
            applied = [:]
        }
        if paused { hideBorder(); updateStatus(); return }
        if overview || creatingDesktop { return }
        // Locked screen / screen saver: apps expose no windows, which would empty the layout.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"].contains(front) {
            hideBorder()
            return
        }
        watchSecureInput()
        runCommandFile()

        timed("observing apps", limit: 1.0) { Profile.phase("observe") { observeApps() } }
        // The Dock animates a switch calmtile asked for; the window server reports the new desktop only when it is
        // done, so a switch of our own is not second-guessed for a moment.
        if config.useSpaces, Date().timeIntervalSince(switchedAt) > 0.8, let n = Spaces.activeNumber(), n != engine.currentWorkspace {
            engine.switchWorkspace(n)   // the user switched desktops by gesture or Mission Control
            switchedAt = Date()
        }

        // 1. reconcile the set of windows
        // Desktops mode: which desktop a window is on comes from the window server, never from its presence in
        // the Accessibility list. That list lags a desktop switch by a moment and still shows the desktop just
        // left; taking those windows as "here" tiled them into the wrong workspace, and focusing one of them
        // then pulled macOS straight back to its desktop.
        let current = timed("listing windows", limit: 1.0) { Profile.phase("list") { Windows.list(excluding: myPid, ignoring: config.ignoreApps) } }
        let reconcileStart = CACurrentMediaTime()
        // While the Dock draws a transition (two or more desktops shown) the per-window reports are not trusted.
        let settled = !config.useSpaces || Spaces.shownSpaces().count <= 1
        var seen = Set<WindowID>()
        for w in current {
            seen.insert(w.id)
            let desktop: Int? = config.useSpaces ? (Spaces.number(ofWindow: w.id) ?? engine.currentWorkspace) : nil
            if Log.debug, let d = desktop, d != engine.currentWorkspace {
                Log.write("Accessibility still lists a window of \(w.bundleID) from desktop \(d) on \(engine.currentWorkspace)")
            }
            // Dragged to another desktop by macOS itself: it now belongs to that workspace.
            if let d = desktop, let home = engine.workspaceOf(w.id), home != 0, home != d {
                if settled, reportedDesktop[w.id] == d { relocateKnown(w.id, to: d, from: home) }
            }
            reportedDesktop[w.id] = desktop
            if known[w.id] == nil {
                let float = !w.resizable || config.floatApps.contains(w.bundleID) || titleFloats(w)
                engine.windowAppeared(w.id, floating: float, frame: float ? Windows.frame(of: w.element) : nil, workspace: desktop)
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
        let focusedBefore = engine.focused
        var focusedClosed = false
        let living: [WindowID: Bool] = config.useSpaces ? Spaces.existingWindows() : [:]
        let justSwitched = Date().timeIntervalSince(switchedAt) < 0.8
        for id in Array(known.keys) where !seen.contains(id) {
            if config.useSpaces, let onscreen = living[id] {
                let n = Spaces.number(ofWindow: id)
                if let n = n, n != engine.currentWorkspace {
                    // On another desktop (not visible to Accessibility right now): keep it, follow it if it moved.
                    if let home = engine.workspaceOf(id), home != 0, home != n, settled, reportedDesktop[id] == n {
                        relocateKnown(id, to: n, from: home)
                    }
                    reportedDesktop[id] = n
                    continue
                }
                // On this desktop but missing from Accessibility: right after a switch the list has simply not
                // caught up yet, so the window stays. Otherwise its app hid, minimized or ordered it out (Word's
                // start gallery, say) and it must not keep a tile.
                if n != nil, onscreen || justSwitched { continue }
            }
            if id == focusedBefore { focusedClosed = true }
            engine.windowGone(id)
            known[id] = nil
            applied[id] = nil
            retries[id] = nil
            self.settled[id] = nil
            reportedDesktop[id] = nil
            titleChecked.remove(id)
        }

        // The focused window was closed: focus returns to the window the engine picked (the last one
        // used on this workspace), not to whatever the OS happens to raise.
        if focusedClosed, !paused, let id = engine.focused, known[id] != nil { focusEngineChoice() }

        if current.count != lastWindowCount {
            Log.write("windows seen=\(current.count) trusted=\(Windows.isTrusted(prompt: false))")
            lastWindowCount = current.count
        }

        Profile.add("reconcile", CACurrentMediaTime() - reconcileStart)

        // 2. follow the focus the user set by clicking / app switching
        Profile.phase("focus") {
            if let f = Windows.focusedWindowID(), known[f.id] != nil, f.id != engine.focused {
                engine.setFocused(f.id)
            }
        }

        // 3. floating windows keep wherever the user put them
        Profile.phase("float") {
            for (id, w) in known where engine.isFloating(id) {
                if case .frame? = applied[id], let f = Windows.frame(of: w.element) { engine.noteFloatFrame(id, f) }
            }
            trackNativeDrag()
            floatByTitle()
        }

        // 4. apply what changed
        timed("placing windows", limit: 1.0) { Profile.phase("place") { applyPlan() } }
        Profile.phase("border") { updateBorder() }
        updateStatus()
        Profile.workspace = engine.currentWorkspace
        Profile.endTick()
    }

    /// Development aid (CALMTILE_DEBUG only): an action written to ~/.config/calmtile/command, e.g. `workspace 2`, runs
    /// on the next tick as if its key had been pressed, without any helper process being launched. Launching a
    /// helper app from a shell makes macOS re-activate the shell's owning app a moment later, and with real desktops
    /// that switches back to that app's desktop, which made every switch look as if it had been undone.
    private static let commandFile = NSString(string: "~/.config/calmtile/command").expandingTildeInPath
    private func runCommandFile() {
        guard Log.debug, let data = FileManager.default.contents(atPath: Controller.commandFile) else { return }
        try? FileManager.default.removeItem(atPath: Controller.commandFile)
        guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let action = Action.parse(line) else { Log.write("command file: not an action"); return }
        Log.write("command file: \(line)")
        _ = perform(action)
    }

    /// macOS moved a window to another desktop (drag in Mission Control, or calmtile's own move): re-home it.
    private func relocateKnown(_ id: WindowID, to n: Int, from home: Int) {
        engine.relocate(id, to: n)
        applied[id] = nil
        Log.write("window of \(known[id]?.bundleID ?? "?") is on desktop \(n) now (was \(home))")
    }

    private func titleFloats(_ w: AXWin) -> Bool {
        guard let words = config.floatTitles[w.bundleID], !words.isEmpty,
              let t = Windows.title(of: w.element)?.lowercased(), !t.isEmpty else { return false }
        return words.contains { t.contains($0.lowercased()) }
    }

    /// Titles often arrive after the window exists (DevTools, playlists): float a tiled window once it matches.
    /// Done once per window, so toggling it back to tiled by hand sticks.
    private var titleChecked = Set<WindowID>()
    private func floatByTitle() {
        for (id, w) in known where !titleChecked.contains(id) && config.floatTitles[w.bundleID] != nil {
            guard !engine.isFloating(id), engine.workspaceOf(id) != 0 else { titleChecked.insert(id); continue }
            if titleFloats(w), let f = Windows.frame(of: w.element) {
                titleChecked.insert(id)
                engine.makeFloating(id, frame: f.insetBy(dx: 0, dy: 0))
                applied[id] = nil
                Log.write("float by title rule (\(w.bundleID))")
            }
        }
    }

    /// A tiled window pulled by its title bar follows the pointer; on release it swaps with the tile under
    /// the pointer, or snaps back to its own tile.
    private func trackNativeDrag() {
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if down {
            guard nativeDrag == nil, drag == nil, let id = engine.focused, !engine.isFloating(id), let w = known[id],
                  case .frame(let want)? = applied[id], let actual = Windows.frame(of: w.element) else { return }
            let rest = settled[id] ?? want
            let moved = hypot(actual.minX - rest.minX, actual.minY - rest.minY) > 8
            let sameSize = abs(actual.width - rest.width) <= 3 && abs(actual.height - rest.height) <= 3
            if moved && sameSize { nativeDrag = id }
        } else if let id = nativeDrag {
            nativeDrag = nil
            let mouse = NSEvent.mouseLocation
            let height = NSScreen.screens.first?.frame.height ?? 0
            let p = CGPoint(x: mouse.x, y: height - mouse.y)
            if let target = engine.tiledFrames().first(where: { $0.key != id && $0.value.contains(p) })?.key {
                engine.swapWindows(id, target)
            }
            applied[id] = nil
            retries[id] = 0
            Log.write("title-bar drag released")
        }
    }

    /// Outline the focused window, unless it is parked, fullscreen-native, or gone. With `borderFlash` the outline
    /// only flashes when the focus moves to another window (and stays on while a mouse drag is in progress).
    private func updateBorder() {
        guard let id = engine.focused, let w = known[id] else { hideBorder(); return }
        if case .hidden? = applied[id] { hideBorder(); return }
        if config.useSpaces {
            // Desktops mode: the window's frame can still be read while it sits on another desktop; no outline then.
            // While the Dock animates a switch the window server still reports the old desktop, so the new window's
            // outline waits until the desktop has arrived instead of appearing over the sliding one.
            if let n = Spaces.number(ofWindow: id), n != engine.currentWorkspace { hideBorder(); return }
            if Spaces.activeNumber() != engine.currentWorkspace { hideBorder(); return }
        }
        guard let f = Windows.frame(of: w.element) else { hideBorder(); return }
        if config.borderFlash > 0 {
            if id == borderShownFor && drag == nil {
                if border.isVisible { border.show(around: f) }   // follow the window while the flash lasts
                return
            }
            borderShownFor = id
            borderTimer?.invalidate()
            let t = Timer(timeInterval: config.borderFlash, repeats: false) { [weak self] _ in self?.border.hide() }
            RunLoop.main.add(t, forMode: .common)
            borderTimer = t
            if Log.debug { Log.write("border flash \(id)") }
        }
        border.show(around: f)
    }

    /// Hide the outline; the focused window flashes again when it next qualifies.
    private func hideBorder() {
        borderShownFor = nil
        borderTimer?.invalidate()
        borderTimer = nil
        border.hide()
    }

    private func applyPlan() {
        let plan = engine.plan()
        let monitors = engine.monitors
        for (id, placement) in plan {
            guard let w = known[id] else { continue }
            if config.useSpaces, let home = engine.workspaceOf(id), home != 0 {
                if case .hidden = placement { continue }              // nothing is parked: the desktops do that
                if home != engine.currentWorkspace { continue }       // lives on another desktop
            }
            if let d = drag, d.id == id, !d.resize || d.floating { continue }   // the user is placing it by hand
            if nativeDrag == id { continue }
            if applied[id] != placement {
                retries[id] = 0
            } else {
                // Same plan as before: only act when the app moved or resized the window itself
                // (a new window opening, an app restoring its own frame). Give up after a few tries
                // for apps whose minimum size cannot fit the tile.
                guard case .frame(let want) = placement, !engine.isFloating(id),
                      let actual = Windows.frame(of: w.element), !Windows.framesMatch(actual, want) else { continue }
                // Larger than its tile: the app insists on a minimum size. After a few tries it stays where our
                // last attempt left it, and that is not an intervention by the app, so do not fight it. A window
                // that is smaller than its tile or sits elsewhere never has that excuse (a set call may have timed
                // out while the app was busy): it is placed again, so a neighbour's close always gives it the room.
                let tooBig = actual.width > want.width + 8 || actual.height > want.height + 8
                if tooBig {
                    guard (retries[id] ?? 0) < 6 else { continue }
                    if let s = settled[id], Windows.framesMatch(actual, s) { continue }
                    retries[id] = (retries[id] ?? 0) + 1
                }
            }
            if Log.debug {
                Log.write("place \(id) \(w.bundleID) want=\(placement) actual=\(Windows.frame(of: w.element).map { "\($0)" } ?? "?") retry=\(retries[id] ?? 0)")
            }
            switch placement {
            case .frame(let r):
                Windows.setFrame(w.element, r)
                if !engine.isFloating(id) { Windows.trimOvershoot(w.element, to: r) }
            case .hidden(let m): Windows.hide(w.element, on: monitors[min(m, monitors.count - 1)])
            }
            applied[id] = placement
            if case .frame = placement { settled[id] = Windows.frame(of: w.element) } else { settled[id] = nil }
            // A minimum size larger than the tile would overlap the neighbours: tell the engine, which
            // makes room for it (or floats the window when the workspace cannot hold it).
            if case .frame(let want) = placement, !engine.isFloating(id), engine.tiledFrames().count > 1,
               let got = settled[id], got.width > want.width + 8 || got.height > want.height + 8 {
                Log.write("minimum size exceeds the tile (\(w.bundleID))")
                engine.noteMinSize(id, want: want.size, got: got.size)
                applied = [:]
                requestTick()
                return
            }
        }
    }

    private func focusEngineChoice() {
        guard let id = engine.focused, let w = known[id] else { return }
        // Activating a window that sits on another desktop makes macOS switch there: never by accident.
        if config.useSpaces, let n = Spaces.number(ofWindow: id), n != engine.currentWorkspace { return }
        Windows.focus(w)
    }

    // MARK: - Themes

    private static var themeFile: String {
        return NSString(string: "~/.config/calmtile/theme").expandingTildeInPath
    }

    /// The theme picked at runtime (kept in ~/.config/calmtile/theme) wins over the config file.
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

    /// `open -a` on a running app only activates it; its windows may all sit on other workspaces
    /// (parked off screen), so nothing would appear here. In that case ask the app for a new window.
    /// Returns true when handled.
    private func openInCurrentWorkspace(_ name: String) -> Bool {
        guard name != "Terminal",   // Terminal gets a fresh window from `open` already
              let running = NSWorkspace.shared.runningApplications.first(where: {
                  $0.activationPolicy == .regular && !$0.isTerminated && ($0.localizedName == name || $0.bundleIdentifier == name)
              }) else { return false }
        let here = engine.windows(in: engine.currentWorkspace)
        if here.contains(where: { known[$0]?.pid == running.processIdentifier }) { return false }
        let pid = running.processIdentifier
        running.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Cmd+N (key code 45) straight to the app: File > New Window in Chrome, Safari, Finder, ...
            let src = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 45, keyDown: down)
                e?.flags = .maskCommand
                e?.postToPid(pid)
            }
        }
        Log.write("open \(name): no window on workspace \(engine.currentWorkspace), requesting a new one")
        return true
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
        let consumed = mouseStep(type, p, flags)
        hotkeys.dragActive = drag != nil
        return consumed
    }

    private func mouseStep(_ type: CGEventType, _ p: CGPoint, _ flags: CGEventFlags) -> Bool {
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

    /// Returns true when the key was consumed. `late`: the key tap already let the key through because this thread
    /// was busy; a focus key is then dropped (the app got its arrow key), everything else still runs.
    private func handle(_ action: Action, late: Bool = false) -> Bool {
        Log.write("hotkey \(action)\(late ? " (late)" : "")")
        if late, case .focus = action { return false }
        if case .togglePause = action { togglePaused(); return true }
        if paused { return false }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           config.passthroughApps.contains(front) {
            return false
        }
        if launcher.isVisible {
            // Only the launcher key itself works while it is open (it closes the panel).
            if case .launcher = action { launcher.hide(); return true }
            if case .appLauncher = action { launcher.hide(); return true }
            return false
        }
        return perform(action)
    }

    private func mouseEvent(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: p,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// macOS offers no way to move a window to another desktop, except dragging it there while the system
    /// shortcut "Switch to Desktop N" (⌃N) fires. So: grab the title bar, press ⌃N (enabled for that moment, see
    /// `Spaces.pressDesktopShortcut`), let go, come back. Moving a window through a private call was tried and
    /// has no effect on macOS 26.
    private func moveFocusedToDesktop(_ n: Int) {
        let from = engine.currentWorkspace
        guard n != from, let id = engine.focused, let w = known[id], let f = Windows.frame(of: w.element) else { return }
        // The system shortcut counts desktops by their position in the Dock's order, not by workspace number.
        guard let position = Spaces.position(of: n), position <= 9 else {
            Log.write("move to desktop \(n): it does not exist yet (go there with the workspace key first)")
            NSSound.beep()
            return
        }
        let grab = CGPoint(x: f.minX + min(80, f.width / 2), y: f.minY + 12)
        let moved = CGPoint(x: grab.x + 6, y: grab.y + 2)
        let saved = CGEvent(source: nil)?.location ?? grab
        hotkeys.suspendMouse = true
        mouseEvent(.leftMouseDown, grab)
        mouseEvent(.leftMouseDragged, moved)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            _ = Spaces.pressDesktopShortcut(position: position)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.mouseEvent(.leftMouseUp, moved)
                CGWarpMouseCursorPosition(saved)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.hotkeys.suspendMouse = false
                    self?.engine.relocate(id, to: n)
                    Spaces.switchTo(from)
                    self?.engine.switchWorkspace(from)
                    self?.applied = [:]
                    Log.write("moved window to desktop \(n)")
                }
            }
        }
    }

    /// Switch workspace; with `useSpaces` that is the Nth macOS desktop, created on the spot when it does not
    /// exist yet (Hyprland semantics: a workspace exists as soon as you go there).
    private func goTo(_ n: Int) {
        hideBorder()   // the outline marks a window of the workspace being left
        if config.useSpaces {
            if Spaces.switchTo(n) { desktopSwitched(to: n, after: 0.05); return }
            guard !creatingDesktop else { return }
            creatingDesktop = true
            Log.write("desktop \(n) does not exist: creating it through Mission Control")
            Spaces.createAndSwitch(to: n) { [weak self] ok in
                guard let self = self else { return }
                self.creatingDesktop = false
                if ok {
                    Log.write("created desktop \(n)")
                    self.desktopSwitched(to: n, after: 0.6)   // the overview closes with an animation
                } else {
                    Log.write("could not create desktop \(n): Mission Control did not show its Spaces bar")
                    NSSound.beep()
                }
            }
            return
        }
        engine.switchWorkspace(n)
        applyPlan()
        focusEngineChoice()
        updateBorder()
    }

    private func desktopSwitched(to n: Int, after delay: TimeInterval) {
        engine.switchWorkspace(n)
        switchedAt = Date()
        applied = [:]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.applyPlan()
            self?.focusEngineChoice()
        }
    }

    private func perform(_ action: Action) -> Bool {
        switch action {
        case .workspace(let n):
            goTo(n)
        case .moveToWorkspace(let n) where config.useSpaces:
            moveFocusedToDesktop(n)
        case .moveToWorkspace(let n):
            engine.moveFocused(toWorkspace: n)
            applyPlan()
            focusEngineChoice()
        case .focus(let d):
            // No neighbour that way: hand the key back (e.g. ⌘← still moves the text cursor).
            guard engine.focus(d) else { return false }
            focusEngineChoice()
            updateBorder()
        case .swap(let d):
            engine.swap(d)
            applyPlan()
        case .resize(let d):
            engine.resize(d)
            applyPlan()
        case .resizeSmart(let grow):
            engine.resizeSmart(grow: grow)
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
        case .moveWorkspaceToMonitor:
            engine.moveWorkspaceToNextMonitor()
            applied = [:]
            applyPlan()
            focusEngineChoice()
        case .backAndForth:
            goTo(engine.previousWorkspace)
        case .reload:
            reload()
        case .open(let app):
            if openInCurrentWorkspace(app) { break }
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
        case .appLauncher:
            launcher.show(appsOnly: true)
        case .theme(let name):
            setTheme(name)
        case .themeNext:
            setTheme(Theme.after(theme.name).name)
        case .togglePause:
            togglePaused()
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
        if secureInput {
            let holder = Spaces.secureInputPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            let hint = NSMenuItem(title: "Hotkeys blocked: secure keyboard entry" + (holder.map { " (\($0))" } ?? ""), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(withTitle: "Reload config", action: #selector(MenuTarget.reload), keyEquivalent: "").target = target
        let sp = menu.addItem(withTitle: "Spotlight: applications only", action: #selector(MenuTarget.toggleSpotlight), keyEquivalent: "")
        sp.target = target
        sp.state = spotlightOn ? .on : .off
        let login = menu.addItem(withTitle: "Start at login", action: #selector(MenuTarget.toggleLogin), keyEquivalent: "")
        login.target = target
        login.state = LoginItem.isInstalled ? .on : .off
        menu.addItem(withTitle: "Pause / resume tiling", action: #selector(MenuTarget.pause), keyEquivalent: "").target = target
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit calmtile", action: #selector(MenuTarget.quit), keyEquivalent: "q").target = target
    }

    fileprivate func menuSelect(_ id: WindowID) {
        guard known[id] != nil else { return }
        engine.activate(id)
        applyPlan()
        focusEngineChoice()
        updateBorder()
    }

    fileprivate func menuReload() { reload() }
    fileprivate func menuPause() { togglePaused() }

    private func togglePaused() {
        paused.toggle()
        updateSpotlight()
        updateStatus()
    }

    // MARK: - Spotlight (apps only)

    /// Spotlight is restricted only while tiling is active and the mode is on.
    private func updateSpotlight() {
        if spotlightOn && !paused { SpotlightMode.enableAppsOnly() } else { SpotlightMode.restore() }
    }

    fileprivate func menuToggleSpotlight() {
        spotlightOn.toggle()
        updateSpotlight()
    }

    /// Restore the system setting however we are asked to stop; a crash is covered by the backup file at next start.
    private var signalSources = [DispatchSourceSignal]()
    private func installTerminationHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { SpotlightMode.restore(); exit(0) }
            src.resume()
            signalSources.append(src)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            SpotlightMode.restore()
        }
    }

    /// Secure Keyboard Entry (Terminal's menu item, password fields, password managers) stops every event tap from
    /// receiving keys; hotkeys silently "do nothing" until it ends. Say so in the menu bar and the log.
    private func watchSecureInput() {
        let on = IsSecureEventInputEnabled()
        guard on != secureInput else { return }
        secureInput = on
        if on {
            let holder = Spaces.secureInputPID().flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            Log.write("secure keyboard entry on (\(holder ?? "holder unknown")): no hotkey can be received until it ends")
        } else {
            Log.write("secure keyboard entry off: hotkeys work again")
        }
        updateStatus()
    }

    private func updateStatus() {
        var title = paused ? "\u{25A6} \u{23F8}" : "\u{25A6} \(engine.currentWorkspace)"
        if secureInput { title += " \u{1F512}" }
        if statusItem?.button?.title != title { statusItem?.button?.title = title }
    }

    private func notify(_ text: String) {
        FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
        let alert = NSAlert()
        alert.messageText = "calmtile"
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
    @objc func toggleLogin() { LoginItem.toggle() }
    @objc func toggleSpotlight() { controller?.menuToggleSpotlight() }
    @objc func quit() { NSApp.terminate(nil) }
}
