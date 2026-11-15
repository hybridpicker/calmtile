import Foundation
import CalmCore

/// Makes Spotlight (⌘Space) list applications only while calmtile runs, and puts the user's own
/// category list back afterwards. This is a system setting, so the original is saved first in
/// ~/.config/calmtile/spotlight-backup.plist and a backup that already exists is never overwritten
/// (it still holds the true original after a crash).
enum SpotlightMode {
    private static let domain = "com.apple.Spotlight" as CFString
    private static let key = "orderedItems" as CFString

    static var backupPath: String {
        return NSString(string: "~/.config/calmtile/spotlight-backup.plist").expandingTildeInPath
    }

    static var hasBackup: Bool { return FileManager.default.fileExists(atPath: backupPath) }

    private static func read() -> Any? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain)
    }

    private static func write(_ value: Any?) {
        CFPreferencesSetAppValue(key, value as CFPropertyList?, domain)
        CFPreferencesAppSynchronize(domain)
    }

    /// Spotlight reads the list when its panel starts: restart it so the change shows up.
    private static func reloadSpotlight() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["-u", NSUserName(), "Spotlight"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
    }

    /// Back up (once), then switch every category except APPLICATIONS off. Idempotent.
    static func enableAppsOnly() {
        if !hasBackup {
            var dict: [String: Any] = ["hadKey": false]
            if let current = read() { dict["hadKey"] = true; dict["orderedItems"] = current }
            do {
                try FileManager.default.createDirectory(atPath: (backupPath as NSString).deletingLastPathComponent,
                                                        withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
                try data.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
            } catch {
                Log.write("spotlight: cannot write backup, leaving Spotlight alone")
                return
            }
        }
        // Derive from the saved original, not from a state we may have changed already.
        let original = savedOriginal()
        let target = SpotlightCategories.appsOnly(from: SpotlightCategories.parse(original))
        write(SpotlightCategories.plist(target))
        reloadSpotlight()
        Log.write("spotlight: apps only")
    }

    /// Put the original list back (or remove the key if there was none) and drop the backup.
    static func restore() {
        guard hasBackup else { return }
        guard let data = FileManager.default.contents(atPath: backupPath),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            Log.write("spotlight: backup unreadable, kept at \(backupPath)")
            return
        }
        write((dict["hadKey"] as? Bool) == true ? dict["orderedItems"] : nil)
        try? FileManager.default.removeItem(atPath: backupPath)
        reloadSpotlight()
        Log.write("spotlight: restored")
    }

    private static func savedOriginal() -> Any? {
        guard let data = FileManager.default.contents(atPath: backupPath),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              (dict["hadKey"] as? Bool) == true else { return nil }
        return dict["orderedItems"]
    }
}

/// Spotlight's own ⌘Space. calmtile's key tap normally takes the key first, but while an app has Secure Keyboard
/// Entry on (Chrome, Word and Finder switch it on for a few seconds at a time, password fields for longer) no tap
/// receives keys and the window server hands ⌘Space to Spotlight instead. So the shortcut is switched off while
/// calmtile owns ⌘Space and back on when it stops. This is window server state only (not written to the
/// preferences, back after a logout); a marker file remembers that calmtile switched it off, so a start after a
/// crash still turns it back on when asked.
enum SpotlightShortcut {
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private typealias IsEnabled = @convention(c) (Int32) -> Bool
    /// "Show Spotlight search" in com.apple.symbolichotkeys.
    private static let showSpotlight: Int32 = 64

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let lib = skyLight, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    private static let setEnabled = symbol("SLSSetSymbolicHotKeyEnabled", as: SetEnabled.self)
    private static let isEnabled = symbol("SLSIsSymbolicHotKeyEnabled", as: IsEnabled.self)

    private static var markerPath: String {
        return NSString(string: "~/.config/calmtile/spotlight-shortcut-off").expandingTildeInPath
    }
    private static var switchedOff: Bool { return FileManager.default.fileExists(atPath: markerPath) }

    /// Idempotent. Leaves a shortcut alone that the user had switched off already.
    static func disable() {
        guard !switchedOff, let set = setEnabled, let get = isEnabled, get(showSpotlight) else { return }
        guard set(showSpotlight, false) == 0 else { Log.write("spotlight shortcut: cannot switch off"); return }
        try? FileManager.default.createDirectory(atPath: (markerPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: markerPath, contents: Data())
        Log.write("spotlight shortcut: off while calmtile owns cmd-space")
    }

    /// Only undoes what `disable` did.
    static func restore() {
        guard switchedOff else { return }
        if let set = setEnabled { _ = set(showSpotlight, true) }
        try? FileManager.default.removeItem(atPath: markerPath)
        Log.write("spotlight shortcut: on again")
    }
}
