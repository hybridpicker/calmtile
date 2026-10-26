import AppKit
import CalmCore

struct LauncherItem {
    enum Kind: Int { case window = 0, action = 1, app = 2 }
    let kind: Kind
    let title: String
    let detail: String
    let run: () -> Void
}

/// Installed applications, scanned from the usual folders. The scan runs off the main thread: once at start, and
/// again in the background when the list is more than a minute old, so opening the launcher never waits for it
/// (only the very first call before the start-up scan has finished does).
enum Apps {
    private static let lock = NSLock()
    private static var cache: [(name: String, url: URL)] = []
    private static var scanned = Date.distantPast
    private static var scanning = false

    static func installed() -> [(name: String, url: URL)] {
        lock.lock()
        let have = cache, never = scanned == .distantPast, age = Date().timeIntervalSince(scanned)
        lock.unlock()
        if never { let fresh = scan(); store(fresh); return fresh }
        if age >= 60 { refresh() }
        return have
    }

    /// Start a background scan unless one is running.
    static func refresh() {
        lock.lock()
        if scanning { lock.unlock(); return }
        scanning = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { store(scan()) }
    }

    private static func store(_ list: [(name: String, url: URL)]) {
        lock.lock()
        cache = list
        scanned = Date()
        scanning = false
        lock.unlock()
    }

    private static func scan() -> [(name: String, url: URL)] {
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    "/System/Library/CoreServices", "/System/Library/CoreServices/Applications",
                    NSString(string: "~/Applications").expandingTildeInPath]
        var seen = Set<String>()
        var out = [(name: String, url: URL)]()
        for d in dirs {
            let url = URL(fileURLWithPath: d)
            let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for e in entries where e.pathExtension == "app" {
                let name = e.deletingPathExtension().lastPathComponent
                if seen.insert(name).inserted { out.append((name, e)) }
            }
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

/// How often each application was started from the launcher, by name only (no titles, no paths), in
/// ~/.config/calmtile/launcher-usage.json. Breaks ties between equally good matches.
enum LauncherUsage {
    private static let file = NSString(string: "~/.config/calmtile/launcher-usage.json").expandingTildeInPath
    private static var counts: [String: Int] = {
        guard let data = FileManager.default.contents(atPath: file),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Int] else { return [:] }
        return obj
    }()

    static func uses(_ name: String) -> Int { return counts[name] ?? 0 }

    static func record(_ name: String) {
        counts[name, default: 0] += 1
        let snapshot = counts
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
            try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: file), options: .atomic)
        }
    }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
}

/// Type to search windows, apps and calmtile actions; arrows + Return to pick, Esc to close.
final class Launcher: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    /// The items to search; `appsOnly` asks for applications alone (no window titles are read then).
    var provider: ((_ appsOnly: Bool) -> [LauncherItem])?
    /// Called right before an item runs or the panel is dismissed, to hand focus back.
    var onClose: (() -> Void)?
    var theme = Theme.all[0] { didSet { applyTheme() } }
    var isVisible: Bool { return panel.isVisible }

    private let panel: LauncherPanel
    private let field = NSTextField()
    private var rowViews = [NSView]()
    private var rowLabels = [NSTextField]()
    private var items = [LauncherItem]()
    private var shown = [LauncherItem]()
    private var selected = 0
    private var closing = false

    private let width: CGFloat = 640
    private let rowHeight: CGFloat = 36
    private let maxRows = 8
    private let header: CGFloat = 68

    override init() {
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 68),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.delegate = self

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 2
        panel.contentView = content

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 22)
        field.placeholderString = "Search windows, apps, actions\u{2026}"
        field.delegate = self
        content.addSubview(field)

        for _ in 0..<maxRows {
            let row = NSView()
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            row.addSubview(label)
            content.addSubview(row)
            rowViews.append(row)
            rowLabels.append(label)
        }
        applyTheme()
    }

    private func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
        return (NSColor(hex: hex) ?? .gray).withAlphaComponent(alpha)
    }

    private func applyTheme() {
        panel.contentView?.layer?.backgroundColor = color(theme.background).cgColor
        panel.contentView?.layer?.borderColor = color(theme.accent).cgColor
        field.textColor = color(theme.foreground)
        redraw()
    }

    /// `appsOnly`: a Spotlight replacement that lists installed and running applications and nothing else.
    func show(appsOnly: Bool = false) {
        let t0 = CACurrentMediaTime()
        shownAt = t0
        items = (provider?(appsOnly) ?? []).filter { !appsOnly || $0.kind == .app }
        field.placeholderString = appsOnly ? "Applications\u{2026}" : "Search windows, apps, actions\u{2026}"
        field.stringValue = ""
        selected = 0
        closing = false
        refilter()
        if let screen = NSScreen.screens.first {
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - f.width / 2, y: screen.frame.maxY - screen.frame.height * 0.28 - f.height))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        // Activation asked for from an event tap completes asynchronously and may be refused once (macOS 14+
        // cooperative activation). Without it the panel is on screen but keys go to the app behind it: ask again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            Log.write("launcher: activation retried (app active=\(NSApp.isActive))")
        }
        Log.write("launcher shown: items=\(items.count) key=\(panel.isKeyWindow) appActive=\(NSApp.isActive) in \(Int((CACurrentMediaTime() - t0) * 1000)) ms")
    }

    func hide(reason: String = "action") {
        guard !closing, panel.isVisible else { return }
        closing = true
        panel.orderOut(nil)
        Log.write("launcher hidden (\(reason))")
        onClose?()
    }

    private func run(_ item: LauncherItem) {
        hide()
        if item.kind == .app { LauncherUsage.record(item.title) }
        item.run()
    }

    private func rank(_ i: LauncherItem, _ score: Int) -> LauncherRank {
        return LauncherRank(score: score, uses: i.kind == .app ? LauncherUsage.uses(i.title) : 0, kind: i.kind.rawValue, title: i.title)
    }

    // MARK: - Search

    private func refilter() {
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            shown = Array(items.sorted { ranksBefore(rank($0, 0), rank($1, 0)) }.prefix(maxRows))
        } else {
            let scored: [(LauncherItem, Int)] = items.compactMap { i in fuzzyScore(q, i.title).map { (i, $0) } }
            shown = Array(scored.sorted { ranksBefore(rank($0.0, $0.1), rank($1.0, $1.1)) }.prefix(maxRows).map { $0.0 })
        }
        selected = 0
        layout()
        redraw()
    }

    private func layout() {
        let rows = shown.count
        let height = header + (rows > 0 ? CGFloat(rows) * rowHeight + 12 : 0)
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        field.frame = NSRect(x: 22, y: height - 54, width: width - 44, height: 36)
        for (i, row) in rowViews.enumerated() {
            row.isHidden = i >= rows
            row.frame = NSRect(x: 10, y: height - header - CGFloat(i + 1) * rowHeight, width: width - 20, height: rowHeight - 2)
            rowLabels[i].frame = NSRect(x: 12, y: 7, width: width - 44, height: 20)
        }
    }

    private func redraw() {
        for (i, row) in rowViews.enumerated() where i < shown.count {
            let item = shown[i]
            let on = i == selected
            row.layer?.backgroundColor = on ? color(theme.accent, alpha: 0.30).cgColor : NSColor.clear.cgColor
            let text = NSMutableAttributedString(string: item.title,
                attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: color(theme.foreground)])
            text.append(NSAttributedString(string: "   " + item.detail,
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color(theme.foreground, alpha: 0.55)]))
            rowLabels[i].attributedStringValue = text
        }
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            if !shown.isEmpty { selected = (selected - 1 + shown.count) % shown.count; redraw() }
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)):
            if !shown.isEmpty { selected = (selected + 1) % shown.count; redraw() }
        case #selector(NSResponder.insertNewline(_:)):
            if selected < shown.count { run(shown[selected]) }
        case #selector(NSResponder.cancelOperation(_:)):
            hide(reason: "escape")
        default:
            return false
        }
        return true
    }

    /// When the panel was asked to show; its becoming key (the moment typing reaches it) is logged against it.
    private var shownAt: CFTimeInterval = 0

    func windowDidBecomeKey(_ notification: Notification) {
        guard shownAt > 0 else { return }
        Log.write("launcher key after \(Int((CACurrentMediaTime() - shownAt) * 1000)) ms")
        shownAt = 0
    }

    func windowDidResignKey(_ notification: Notification) { hide(reason: "lost key window, app active=\(NSApp.isActive)") }
}
