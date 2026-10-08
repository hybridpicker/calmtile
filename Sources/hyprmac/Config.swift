import AppKit
import CoreGraphics
import Foundation
import HyprCore

struct Mods: OptionSet, Hashable {
    let rawValue: Int
    static let cmd = Mods(rawValue: 1)
    static let alt = Mods(rawValue: 2)
    static let ctrl = Mods(rawValue: 4)
    static let shift = Mods(rawValue: 8)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(flags: CGEventFlags) {
        var m = Mods()
        if flags.contains(.maskCommand) { m.insert(.cmd) }
        if flags.contains(.maskAlternate) { m.insert(.alt) }
        if flags.contains(.maskControl) { m.insert(.ctrl) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        self = m
    }
}

struct KeyCombo: Hashable {
    let keyCode: Int64
    let mods: Mods
}

enum Action {
    case workspace(Int)
    case moveToWorkspace(Int)
    case focus(Direction)
    case swap(Direction)
    case resize(Direction)
    case toggleFloat
    case toggleFullscreen
    case toggleSplit
    case close
    case backAndForth
    case reload
    case togglePause
    case open(String)

    static func parse(_ s: String) -> Action? {
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let cmd = parts.first else { return nil }
        let arg = parts.count > 1 ? parts[1] : ""
        switch cmd {
        case "workspace": return Int(arg).map { .workspace($0) }
        case "move-to-workspace": return Int(arg).map { .moveToWorkspace($0) }
        case "focus": return Direction(rawValue: arg).map { .focus($0) }
        case "swap": return Direction(rawValue: arg).map { .swap($0) }
        case "resize": return Direction(rawValue: arg).map { .resize($0) }
        case "toggle-float": return .toggleFloat
        case "toggle-fullscreen": return .toggleFullscreen
        case "toggle-split": return .toggleSplit
        case "close": return .close
        case "back-and-forth": return .backAndForth
        case "reload": return .reload
        case "pause": return .togglePause
        case "open": return arg.isEmpty ? nil : .open(arg)
        default: return nil
        }
    }
}

/// Physical (ANSI) key codes, so bindings behave the same on German and US layouts.
let keyCodes: [String: Int64] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26,
    "minus": 27, "8": 28, "0": 29, "rightbracket": 30, "o": 31, "u": 32, "leftbracket": 33,
    "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41,
    "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47, "tab": 48,
    "space": 49, "backtick": 50, "delete": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

func parseCombo(_ s: String) -> KeyCombo? {
    var mods = Mods()
    var key: Int64?
    for part in s.lowercased().split(separator: "-").map(String.init) {
        switch part {
        case "cmd", "super": mods.insert(.cmd)
        case "alt", "opt", "option": mods.insert(.alt)
        case "ctrl", "control": mods.insert(.ctrl)
        case "shift": mods.insert(.shift)
        default:
            guard let code = keyCodes[part] else { return nil }
            key = code
        }
    }
    guard let k = key, !mods.isEmpty else { return nil }   // bare keys are never grabbed
    return KeyCombo(keyCode: k, mods: mods)
}

struct Config {
    var gap: CGFloat = 4
    var outerGap: CGFloat = 6
    /// Workspaces 1...mainWorkspaces live on the main display, the rest on the second one.
    var mainWorkspaces = 5
    /// Apps whose windows float instead of tiling.
    var floatApps: [String] = [
        "com.apple.systempreferences", "com.apple.calculator", "com.apple.ActivityMonitor",
        "com.apple.archiveutility", "com.apple.PreferencePanes.Preview",
    ]
    /// While one of these apps is frontmost, no hotkey is intercepted.
    var passthroughApps: [String] = []
    /// Outline around the focused window; borderWidth 0 turns it off.
    var borderWidth: CGFloat = 3
    var borderRadius: CGFloat = 12
    var borderColor = "#89b4fa"
    var bindings: [String: String] = Config.defaultBindings

    static var defaultBindings: [String: String] = {
        var b = [String: String]()
        for n in 1...9 {
            b["cmd-\(n)"] = "workspace \(n)"
            b["cmd-alt-\(n)"] = "move-to-workspace \(n)"
        }
        for (name, dir) in [("left", "left"), ("right", "right"), ("up", "up"), ("down", "down")] {
            b["ctrl-alt-\(name)"] = "focus \(dir)"
            b["ctrl-alt-shift-\(name)"] = "swap \(dir)"
            b["ctrl-alt-cmd-\(name)"] = "resize \(dir)"
        }
        for (k, dir) in [("h", "left"), ("l", "right"), ("k", "up"), ("j", "down")] {
            b["ctrl-alt-\(k)"] = "focus \(dir)"
        }
        b["ctrl-alt-f"] = "toggle-fullscreen"
        b["ctrl-alt-t"] = "toggle-float"
        b["ctrl-alt-s"] = "toggle-split"
        b["ctrl-alt-w"] = "close"
        b["ctrl-alt-tab"] = "back-and-forth"
        b["ctrl-alt-r"] = "reload"
        b["ctrl-alt-p"] = "pause"
        b["cmd-return"] = "open Terminal"
        b["ctrl-alt-return"] = "open Terminal"
        return b
    }()

    static var path: String {
        return NSString(string: "~/.config/hyprmac/config.json").expandingTildeInPath
    }

    /// Defaults, overridden by ~/.config/hyprmac/config.json. A binding set to "" removes the default.
    static func load() -> (Config, [String]) {
        var cfg = Config()
        var problems = [String]()
        if let data = FileManager.default.contents(atPath: path) {
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return (cfg, ["config.json is not a JSON object - using defaults"])
            }
            if let v = obj["gap"] as? Double { cfg.gap = CGFloat(v) }
            if let v = obj["outerGap"] as? Double { cfg.outerGap = CGFloat(v) }
            if let v = obj["borderWidth"] as? Double { cfg.borderWidth = CGFloat(v) }
            if let v = obj["borderRadius"] as? Double { cfg.borderRadius = CGFloat(v) }
            if let v = obj["borderColor"] as? String {
                if NSColor(hex: v) == nil { problems.append("borderColor must look like #rrggbb: \(v)") } else { cfg.borderColor = v }
            }
            if let v = obj["mainWorkspaces"] as? Int { cfg.mainWorkspaces = v }
            if let v = obj["floatApps"] as? [String] { cfg.floatApps = v }
            if let v = obj["passthroughApps"] as? [String] { cfg.passthroughApps = v }
            if let v = obj["bindings"] as? [String: String] {
                for (k, a) in v {
                    if a.isEmpty { cfg.bindings[k] = nil } else { cfg.bindings[k] = a }
                }
            }
        }
        for (k, a) in cfg.bindings {
            if parseCombo(k) == nil { problems.append("unknown key combination: \(k)") }
            if Action.parse(a) == nil { problems.append("unknown action for \(k): \(a)") }
        }
        return (cfg, problems)
    }

    func table() -> [KeyCombo: Action] {
        var t = [KeyCombo: Action]()
        for (k, a) in bindings {
            if let c = parseCombo(k), let act = Action.parse(a) { t[c] = act }
        }
        return t
    }

    func json() -> String {
        let obj: [String: Any] = [
            "gap": Double(gap), "outerGap": Double(outerGap), "mainWorkspaces": mainWorkspaces,
            "borderWidth": Double(borderWidth), "borderRadius": Double(borderRadius), "borderColor": borderColor,
            "floatApps": floatApps, "passthroughApps": passthroughApps, "bindings": bindings,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
