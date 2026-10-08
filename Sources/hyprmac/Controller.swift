import AppKit
import HyprCore

final class Controller {
    private var config: Config
    private let engine: Engine
    private let hotkeys = HotkeyTap()
    private var known = [WindowID: AXWin]()
    private var applied = [WindowID: Placement]()
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var paused = false
    private var monitorsDirty = true
    private let myPid = ProcessInfo.processInfo.processIdentifier

    init() {
        let (cfg, _) = Config.load()
        config = cfg
        engine = Engine(monitors: Screens.monitors())
        applyConfig()
    }

    // MARK: - Lifecycle

    func start() {
        if !Windows.isTrusted(prompt: true) {
            notify("Allow hyprmac under System Settings > Privacy & Security > Accessibility, then start it again.")
        }
        setUpMenu()
        hotkeys.handler = { [weak self] action in self?.handle(action) ?? false }
        if !hotkeys.start() {
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
    }

    private func reload() {
        let (cfg, problems) = Config.load()
        config = cfg
        applyConfig()
        monitorsDirty = true
        applied = [:]
        if !problems.isEmpty { notify(problems.joined(separator: "\n")) }
    }

    // MARK: - The loop

    private func tick() {
        if monitorsDirty {
            engine.setMonitors(Screens.monitors())
            monitorsDirty = false
            applied = [:]
        }
        if paused { updateStatus(); return }

        // 1. reconcile the set of windows
        let current = Windows.list(excluding: myPid)
        var seen = Set<WindowID>()
        for w in current {
            seen.insert(w.id)
            if known[w.id] == nil {
                let float = !w.resizable || config.floatApps.contains(w.bundleID)
                engine.windowAppeared(w.id, floating: float, frame: float ? Windows.frame(of: w.element) : nil)
            }
            known[w.id] = w
        }
        for id in Array(known.keys) where !seen.contains(id) {
            engine.windowGone(id)
            known[id] = nil
            applied[id] = nil
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
        updateStatus()
    }

    private func applyPlan() {
        let plan = engine.plan()
        let monitors = engine.monitors
        for (id, placement) in plan {
            guard let w = known[id], applied[id] != placement else { continue }
            switch placement {
            case .frame(let r): Windows.setFrame(w.element, r)
            case .hidden(let m): Windows.hide(w.element, on: monitors[min(m, monitors.count - 1)])
            }
            applied[id] = placement
        }
    }

    private func focusEngineChoice() {
        if let id = engine.focused, let w = known[id] { Windows.focus(w) }
    }

    // MARK: - Hotkeys

    /// Returns true when the key was consumed.
    private func handle(_ action: Action) -> Bool {
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
            if engine.focus(d) { focusEngineChoice() }
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
            p.arguments = ["-a", app]
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
