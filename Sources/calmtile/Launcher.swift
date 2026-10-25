import AppKit
import CalmCore

struct LauncherItem {
    enum Kind: Int { case window = 0, action = 1, app = 2 }
    let kind: Kind
    let title: String
    let detail: String
    let run: () -> Void
}

/// Installed applications, scanned from the usual folders and cached for a minute.
enum Apps {
    private static var cache: [(name: String, url: URL)] = []
    private static var scanned = Date.distantPast

    static func installed() -> [(name: String, url: URL)] {
        if Date().timeIntervalSince(scanned) < 60 { return cache }
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
        cache = out.sorted { $0.name.lowercased() < $1.name.lowercased() }
        scanned = Date()
        return cache
    }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
}

/// Type to search windows, apps and calmtile actions; arrows + Return to pick, Esc to close.
final class Launcher: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var provider: (() -> [LauncherItem])?
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
        items = (provider?() ?? []).filter { !appsOnly || $0.kind == .app }
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
        Log.write("launcher shown: items=\(items.count) key=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
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
        item.run()
    }

    // MARK: - Search

    private func refilter() {
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            shown = Array(items.sorted { ($0.kind.rawValue, $0.title.lowercased()) < ($1.kind.rawValue, $1.title.lowercased()) }.prefix(maxRows))
        } else {
            let scored: [(LauncherItem, Int)] = items.compactMap { i in fuzzyScore(q, i.title).map { (i, $0) } }
            shown = Array(scored.sorted {
                $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.kind.rawValue < $1.0.kind.rawValue
            }.prefix(maxRows).map { $0.0 })
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

    func windowDidResignKey(_ notification: Notification) { hide(reason: "lost key window, app active=\(NSApp.isActive)") }
}
