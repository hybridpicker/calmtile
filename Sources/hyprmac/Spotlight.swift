import Foundation
import HyprCore

/// Makes Spotlight (⌘Space) list applications only while hyprmac runs, and puts the user's own
/// category list back afterwards. This is a system setting, so the original is saved first in
/// ~/.config/hyprmac/spotlight-backup.plist and a backup that already exists is never overwritten
/// (it still holds the true original after a crash).
enum SpotlightMode {
    private static let domain = "com.apple.Spotlight" as CFString
    private static let key = "orderedItems" as CFString

    static var backupPath: String {
        return NSString(string: "~/.config/hyprmac/spotlight-backup.plist").expandingTildeInPath
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
