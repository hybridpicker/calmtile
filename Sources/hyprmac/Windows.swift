import AppKit
import ApplicationServices
import HyprCore

// Private but long-stable API (also used by AeroSpace, yabai, Rectangle): AXUIElement -> CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct AXWin {
    let id: WindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let resizable: Bool
}

enum Screens {
    /// Monitors in Accessibility coordinates (origin top-left of the main display, y down),
    /// usable area only (below the menu bar, beside the Dock). Main display first, then left to right.
    static func monitors() -> [Monitor] {
        let all = NSScreen.screens
        guard let main = all.first else { return [] }
        let mainHeight = main.frame.height
        let ordered = [main] + all.dropFirst().sorted { $0.frame.minX < $1.frame.minX }
        return ordered.enumerated().map { (i, s) in
            let v = s.visibleFrame
            return Monitor(id: i, frame: CGRect(x: v.minX, y: mainHeight - v.maxY, width: v.width, height: v.height))
        }
    }
}

enum Windows {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &ref) == .success else { return nil }
        return ref as? T
    }

    static func list(excluding selfPid: pid_t) -> [AXWin] {
        var out = [AXWin]()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != selfPid && !$0.isTerminated }
        for app in apps {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.25)
            guard let wins: [AXUIElement] = attr(ax, kAXWindowsAttribute) else { continue }
            for w in wins {
                let role: String? = attr(w, kAXRoleAttribute)
                let subrole: String? = attr(w, kAXSubroleAttribute)
                guard role == kAXWindowRole as String, subrole == "AXStandardWindow" else { continue }
                if let min: Bool = attr(w, kAXMinimizedAttribute), min { continue }
                if let fs: Bool = attr(w, "AXFullScreen"), fs { continue }   // native macOS fullscreen: leave alone
                var wid = CGWindowID(0)
                guard _AXUIElementGetWindow(w, &wid) == .success, wid != 0 else { continue }
                var settable = DarwinBoolean(false)
                _ = AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &settable)
                out.append(AXWin(id: wid, element: w, pid: app.processIdentifier,
                                 bundleID: app.bundleIdentifier ?? "?", resizable: settable.boolValue))
            }
        }
        return out
    }

    static func frame(of el: AXUIElement) -> CGRect? {
        guard let p: AXValue = attr(el, kAXPositionAttribute), let s: AXValue = attr(el, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &pos), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// True when two frames agree within a few pixels (apps round and clamp).
    static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        return abs(a.minX - b.minX) <= 3 && abs(a.minY - b.minY) <= 3
            && abs(a.width - b.width) <= 3 && abs(a.height - b.height) <= 3
    }

    static func setFrame(_ el: AXUIElement, _ r: CGRect) {
        var pos = r.origin
        var size = r.size
        // size, position, size: apps clamp the size to the screen they are currently on.
        var codes = [AXError]()
        if let sv = AXValueCreate(.cgSize, &size) { codes.append(AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv)) }
        if let pv = AXValueCreate(.cgPoint, &pos) { codes.append(AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv)) }
        if let sv = AXValueCreate(.cgSize, &size) { codes.append(AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv)) }
        if Log.debug { Log.write("  set -> \(codes.map { $0.rawValue }) now=\(frame(of: el).map { "\($0)" } ?? "?")") }
    }

    static func setPosition(_ el: AXUIElement, _ p: CGPoint) {
        var pos = p
        if let pv = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv) }
    }

    static func setSize(_ el: AXUIElement, _ s: CGSize) {
        var size = s
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv) }
    }

    /// Topmost normal window under `p` (Accessibility coordinates), front to back.
    static func windowID(at p: CGPoint) -> WindowID? {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID),
              let list = (raw as NSArray) as? [[String: Any]] else { return nil }
        for w in list {
            guard (w["kCGWindowLayer"] as? Int) == 0,
                  let num = w["kCGWindowNumber"] as? Int,
                  let b = w["kCGWindowBounds"] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.contains(p) else { continue }
            return WindowID(num)
        }
        return nil
    }

    /// Park a window at the bottom-right corner of its monitor so only one pixel stays on screen.
    static func hide(_ el: AXUIElement, on monitor: Monitor) {
        var pos = CGPoint(x: monitor.frame.maxX - 1, y: monitor.frame.maxY - 1)
        if let pv = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv) }
    }

    static func focus(_ w: AXWin) {
        AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(w.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: w.pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    static func close(_ w: AXWin) {
        guard let btn: AXUIElement = attr(w.element, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(btn, kAXPressAction as CFString)
    }

    /// The window that currently has keyboard focus, if any.
    static func focusedWindowID() -> (id: WindowID, bundleID: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        guard let w: AXUIElement = attr(ax, kAXFocusedWindowAttribute) else { return nil }
        var wid = CGWindowID(0)
        guard _AXUIElementGetWindow(w, &wid) == .success, wid != 0 else { return nil }
        return (wid, app.bundleIdentifier ?? "?")
    }
}
