import AppKit
import IOKit.ps

/// A fixed bar along the top of the main display (Omarchy's Waybar): the workspaces on the left, day and time in the
/// middle, the battery on the right. The tiles start below it (`Screens.monitors(barHeight:)`). It is on every
/// desktop but not over native fullscreen apps, and goes away while Mission Control is open. A click on a workspace number goes
/// there without taking the focus from the window below (non-activating panel). Shows no window titles.
final class TopBar {
    struct State: Equatable {
        var count = 5
        var current = 1
        var occupied = Set<Int>()
    }

    private let panel: NSPanel
    private let view: BarView
    private var clockTimer: Timer?
    /// Where `show` last put the bar; nil while the bar is off.
    private var wanted: NSRect?
    /// Mission Control or App Exposé is open (from the Dock's notifications), and since when.
    private var overviewSince: Date?
    private var dockObserver: AXObserver?
    private var dockPid: pid_t = 0
    var onWorkspace: ((Int) -> Void)? {
        get { view.onWorkspace }
        set { view.onWorkspace = newValue }
    }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Above the menu bar and its status items: with the menu bar set to hide, the one macOS slides in when the
        // pointer touches the top edge then stays behind this bar (no setting can stop it from sliding in), and
        // clicks up there reach the bar. Below pop-up menus. With the menu bar always shown the bar covers it
        // (`Screens.barFrame`), which keeps Finder's desktop icons below the bar.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        // Stationary: a desktop switch leaves it where it is. With `.transient` instead macOS took it away for the
        // length of every switch and put it back afterwards (seen as a blink). Mission Control draws its own
        // full-screen windows on layers 18 and 20 (measured), under this bar, so it is taken away while that is open.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        view = BarView()
        panel.contentView = view
    }

    func configure(background: NSColor, foreground: NSColor, height: CGFloat) {
        panel.backgroundColor = background
        view.background = background
        view.foreground = foreground
        view.height = height
        view.needsDisplay = true
    }

    /// `frame` in Accessibility coordinates (origin top-left of the main display, y down).
    func show(at frame: CGRect) {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return }
        let r = NSRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
        wanted = r
        watchDock()
        // A missed exit notification (the Dock restarted meanwhile) must not keep the bar away for good.
        if let since = overviewSince, Date().timeIntervalSince(since) > 1.5, !Windows.overviewOpen() { overviewSince = nil }
        if overviewSince != nil { if panel.isVisible { panel.orderOut(nil) }; return }
        if panel.frame != r { panel.setFrame(r, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        if clockTimer == nil {
            refreshClock()
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refreshClock() }
            RunLoop.main.add(t, forMode: .common)
            clockTimer = t
        }
    }

    func hide() {
        wanted = nil
        clockTimer?.invalidate()
        clockTimer = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    func update(_ state: State) {
        if view.state != state { view.state = state; view.needsDisplay = true }
    }

    /// The Dock announces Mission Control, App Exposé and Show Desktop through Accessibility notifications on its
    /// application element (the names yabai listens to as well). Registered again when the Dock has restarted.
    private func watchDock() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let pid = dock.processIdentifier
        if pid == dockPid, dockObserver != nil { return }
        if let old = dockObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
            dockObserver = nil
        }
        dockPid = pid
        overviewSince = nil
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, name, refcon in
            guard let refcon = refcon else { return }
            Unmanaged<TopBar>.fromOpaque(refcon).takeUnretainedValue().dockSaid(name as String)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for name in TopBar.openNotifications + [TopBar.exitNotification] {
            AXObserverAddNotification(observer, app, name as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        dockObserver = observer
    }

    private static let openNotifications = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop"]
    private static let exitNotification = "AXExposeExit"

    private func dockSaid(_ name: String) {
        if TopBar.openNotifications.contains(name) {
            overviewSince = Date()
            if panel.isVisible { panel.orderOut(nil) }
        } else if name == TopBar.exitNotification {
            overviewSince = nil
            if let r = wanted {
                if panel.frame != r { panel.setFrame(r, display: true) }
                panel.orderFrontRegardless()
            }
        }
    }

    private func refreshClock() {
        let clock = BarView.clockFormatter.string(from: Date())
        let battery = TopBar.battery()
        if clock != view.clock || battery != view.battery {
            view.clock = clock
            view.battery = battery
            view.needsDisplay = true
        }
    }

    /// "83%" of the internal battery, with "+" while it charges; nil on a Mac without one.
    static func battery() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            return "\(charging ? "+" : "")\(Int((Double(now) / Double(max) * 100).rounded()))%"
        }
        return nil
    }
}

private final class BarView: NSView {
    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEEE HH:mm")   // Omarchy: "%A %H:%M"
        return f
    }()

    var state = TopBar.State()
    var clock = ""
    var battery: String?
    var background = NSColor.black
    var foreground = NSColor.white
    var height: CGFloat = 26
    var onWorkspace: ((Int) -> Void)?
    /// Hit areas of the workspace numbers, from the last draw.
    private var slots = [(n: Int, rect: NSRect)]()

    override var isFlipped: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    private var font: NSFont { return NSFont.monospacedSystemFont(ofSize: max(10, (height * 0.46).rounded()), weight: .regular) }
    private var bold: NSFont { return NSFont.monospacedSystemFont(ofSize: max(10, (height * 0.46).rounded()), weight: .bold) }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        let dim = foreground.withAlphaComponent(0.45)
        // Left: the workspaces. The current one bold with a line under it, occupied ones full, empty ones dim.
        slots = []
        var x: CGFloat = 10
        let slotWidth = (height * 0.9).rounded()
        for n in 1...max(1, state.count) {
            let current = n == state.current
            let color = current || state.occupied.contains(n) ? foreground : dim
            let text = NSAttributedString(string: "\(n)", attributes: [.font: current ? bold : font, .foregroundColor: color])
            let size = text.size()
            let slot = NSRect(x: x, y: 0, width: slotWidth, height: bounds.height)
            text.draw(at: NSPoint(x: slot.midX - size.width / 2, y: (bounds.height - size.height) / 2))
            if current {
                foreground.setFill()
                NSRect(x: slot.midX - 6, y: bounds.height - 3, width: 12, height: 2).fill()
            }
            slots.append((n, slot))
            x += slotWidth
        }
        // Middle: day and time.
        let c = NSAttributedString(string: clock, attributes: [.font: font, .foregroundColor: foreground])
        let cs = c.size()
        c.draw(at: NSPoint(x: (bounds.width - cs.width) / 2, y: (bounds.height - cs.height) / 2))
        // Right: the battery.
        if let b = battery {
            let t = NSAttributedString(string: b, attributes: [.font: font, .foregroundColor: foreground])
            let s = t.size()
            t.draw(at: NSPoint(x: bounds.width - s.width - 12, y: (bounds.height - s.height) / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = slots.first(where: { $0.rect.contains(p) }) { onWorkspace?(hit.n) }
    }
}
