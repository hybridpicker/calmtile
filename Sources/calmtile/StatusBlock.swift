import AppKit
import IOKit.ps

/// calmtile's own status block over the right end of the menu bar (`menuBarStatus`): workspace, battery, day and
/// time, evenly spaced, on the menu bar's colour. macOS 26 lets no app remove the Control Center icon or close the
/// gap it would leave, so the block covers all status items instead. The app menus on the left stay free.
/// Click-through: a click still reaches the status item underneath (calmtile's own menu sits under the `▦`).
final class StatusBlock {
    private let panel: NSPanel
    private let view = StatusBlockView()
    private var clockTimer: Timer?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        // Above the status items, below pop-up menus (Control Center's panel, calmtile's menu), like the bar.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = view
    }

    var color = NSColor.black {
        didSet { panel.backgroundColor = color; view.background = color; view.needsDisplay = true }
    }

    /// `workspace` is the status item's title ("▦ 1", "▦ ⏸", with "🔒" during secure input).
    func show(workspace: String) {
        guard let main = NSScreen.screens.first else { hide(); return }
        let menuBar = main.frame.maxY - main.visibleFrame.maxY
        guard menuBar > 0 else { hide(); return }
        if view.workspace != workspace { view.workspace = workspace; view.needsDisplay = true }
        if clockTimer == nil {
            refreshClock()
            let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refreshClock() }
            RunLoop.main.add(t, forMode: .common)
            clockTimer = t
        }
        // From a little left of the leftmost status item (or as far as the contents need) to the right edge.
        let right = main.frame.maxX
        let left = min(StatusBlock.leftmostStatusItem(on: main, menuBar: menuBar) ?? right, right - view.contentWidth()) - 8
        let r = NSRect(x: left, y: main.frame.maxY - menuBar, width: right - left, height: menuBar)
        if panel.frame != r { panel.setFrame(r, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        clockTimer?.invalidate()
        clockTimer = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func refreshClock() {
        let clock = StatusBlockView.clockText(Date())
        let battery = StatusBlock.battery()
        if clock != view.clock || battery != view.battery {
            view.clock = clock
            view.battery = battery
            view.needsDisplay = true
        }
    }

    /// Left edge (AppKit x) of the leftmost status item on the main display's menu bar. Since macOS 26 Control
    /// Center hosts every app's status item as its own window on the status level, so the window list has them all.
    private static func leftmostStatusItem(on main: NSScreen, menuBar: CGFloat) -> CGFloat? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let level = Int(CGWindowLevelForKey(.statusWindow))
        let me = ProcessInfo.processInfo.processIdentifier
        var left: CGFloat?
        for w in list {
            guard w[kCGWindowLayer as String] as? Int == level,
                  w[kCGWindowOwnerPID as String] as? Int32 != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  y == 0, height <= menuBar + 1, width < main.frame.width / 2,
                  x >= main.frame.minX, x < main.frame.maxX else { continue }
            left = min(left ?? x, x)
        }
        return left
    }

    /// Charge of the internal battery in percent and whether it charges; nil on a Mac without one.
    struct Battery: Equatable { let percent: Int; let charging: Bool }

    static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Battery(percent: Int((Double(now) / Double(max) * 100).rounded()), charging: d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}

private final class StatusBlockView: NSView {
    var workspace = ""
    var clock = ""
    var battery: StatusBlock.Battery?
    var background = NSColor.black
    private let foreground = NSColor.white
    private let spacing: CGFloat = 18
    private let rightPadding: CGFloat = 10

    override var isFlipped: Bool { return true }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("dMMM")   // "23. Nov.", without the weekday
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f
    }()
    static func clockText(_ date: Date) -> String {
        return "\(dayFormatter.string(from: date))  \(timeFormatter.string(from: date))"
    }
    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.locale = Locale.current
        return f
    }()

    private var font: NSFont { return NSFont.menuBarFont(ofSize: 0) }

    /// The pieces from left to right: text, or the battery symbol followed by its text.
    private func pieces() -> [(symbol: NSImage?, text: NSAttributedString)] {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        var out = [(symbol: NSImage?, text: NSAttributedString)]()
        if !workspace.isEmpty { out.append((nil, NSAttributedString(string: workspace, attributes: attrs))) }
        if let b = battery {
            let name = b.charging ? "battery.100percent.bolt"
                : "battery.\([0, 25, 50, 75, 100].min(by: { abs($0 - b.percent) < abs($1 - b.percent) }) ?? 100)percent"
            let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [foreground]))
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            let text = StatusBlockView.percentFormatter.string(from: NSNumber(value: Double(b.percent) / 100)) ?? "\(b.percent)%"
            out.append((symbol, NSAttributedString(string: text, attributes: attrs)))
        }
        if !clock.isEmpty { out.append((nil, NSAttributedString(string: clock, attributes: attrs))) }
        return out
    }

    private func width(_ p: (symbol: NSImage?, text: NSAttributedString)) -> CGFloat {
        return (p.symbol.map { $0.size.width + 5 } ?? 0) + ceil(p.text.size().width)
    }

    func contentWidth() -> CGFloat {
        let ps = pieces()
        return ps.reduce(0) { $0 + width($1) } + spacing * CGFloat(max(0, ps.count - 1)) + rightPadding
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        var x = bounds.width - rightPadding
        for p in pieces().reversed() {
            x -= width(p)
            var px = x
            if let s = p.symbol {
                s.draw(in: NSRect(x: px, y: (bounds.height - s.size.height) / 2, width: s.size.width, height: s.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                px += s.size.width + 5
            }
            p.text.draw(at: NSPoint(x: px, y: (bounds.height - p.text.size().height) / 2))
            x -= spacing
        }
    }
}
