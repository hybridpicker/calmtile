import AppKit
import HyprCore

// Private but long-stable read APIs of the window server (also used by yabai, AeroSpace-like tools).
// Switching the current Space works without special privileges on macOS 26; moving windows between
// Spaces does not (verified: CGSMoveWindowsToManagedSpace has no effect), so hyprmac never tries.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ cid: Int32) -> UInt64
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("CGSManagedDisplaySetCurrentSpace") private func CGSManagedDisplaySetCurrentSpace(_ cid: Int32, _ display: CFString, _ space: UInt64)
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray?

/// macOS desktops of the display that holds the active Space; workspace N is the Nth normal desktop.
enum Spaces {
    private static let cid = CGSMainConnectionID()

    private struct Layout {
        let display: String
        let spaces: [UInt64]   // normal desktops only (full-screen app Spaces are left out)
    }

    private static func layout() -> Layout? {
        guard let all = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return nil }
        let active = CGSGetActiveSpace(cid)
        var fallback: Layout?
        for d in all {
            guard let id = d["Display Identifier"] as? String, let list = d["Spaces"] as? [[String: Any]] else { continue }
            let normal = list.filter { ($0["type"] as? Int) == 0 }.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
            let l = Layout(display: id, spaces: normal)
            if list.contains(where: { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == active }) { return l }
            if fallback == nil { fallback = l }
        }
        return fallback
    }

    static var count: Int { return layout()?.spaces.count ?? 0 }

    /// 1-based desktop number of the active Space, nil when a full-screen app Space is active.
    static func activeNumber() -> Int? {
        guard let l = layout(), let i = l.spaces.firstIndex(of: CGSGetActiveSpace(cid)) else { return nil }
        return i + 1
    }

    @discardableResult
    static func switchTo(_ number: Int) -> Bool {
        guard let l = layout(), number >= 1, number <= l.spaces.count else { return false }
        CGSManagedDisplaySetCurrentSpace(cid, l.display as CFString, l.spaces[number - 1])
        return true
    }

    /// Desktop number a window lives on (nil: unknown, full-screen Space or on another display).
    static func number(ofWindow id: WindowID) -> Int? {
        guard let l = layout(),
              let out = CGSCopySpacesForWindows(cid, 7, [NSNumber(value: id)] as CFArray) as? [NSNumber],
              let space = out.first?.uint64Value, let i = l.spaces.firstIndex(of: space) else { return nil }
        return i + 1
    }

    /// Every normal window that exists, on any Space (the Accessibility list only shows the current one).
    static func existingWindowIDs() -> Set<WindowID> {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID),
              let list = (raw as NSArray) as? [[String: Any]] else { return [] }
        var out = Set<WindowID>()
        for w in list where (w["kCGWindowLayer"] as? Int) == 0 {
            if let n = w["kCGWindowNumber"] as? Int { out.insert(WindowID(n)) }
        }
        return out
    }
}

extension Spaces {
    /// Is the system shortcut "Switch to Desktop N" (Keyboard > Keyboard Shortcuts > Mission Control) enabled?
    static func desktopShortcutEnabled(_ n: Int) -> Bool {
        let raw = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        guard let all = raw as? [String: Any], let entry = all[String(117 + n)] as? [String: Any] else { return false }
        return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int).map { $0 != 0 } ?? false)
    }
}
