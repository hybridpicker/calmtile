import Foundation

/// Turns the trackpad's four-finger gestures off while calmtile runs (swipe between desktops, Mission Control,
/// App Exposé, pinch for Launchpad / desktop) and puts the user's own values back afterwards. Three-finger gestures and
/// the rest are left alone. A system setting, so the original is saved first in ~/.config/calmtile/gestures-backup.plist
/// and a backup that already exists is never overwritten (it still holds the true original after a crash).
enum FourFingerGestures {
    private static let trackpads = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    private static let trackpadKeys = ["TrackpadFourFingerHorizSwipeGesture", "TrackpadFourFingerVertSwipeGesture", "TrackpadFourFingerPinchGesture"]
    /// The Dock decides Mission Control, App Exposé, Launchpad and show-desktop; these keys are what System Settings
    /// writes there. The Dock reads them at its start, so it is restarted when they change.
    private static let dock = "com.apple.dock"
    private static let dockKeys = ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled",
                                   "showDesktopGestureEnabled", "showLaunchpadGestureEnabled"]

    /// Every (domain, key, value when off) this switch owns.
    private static var targets: [(domain: String, key: String, off: NSNumber)] {
        return trackpads.flatMap { d in trackpadKeys.map { (d, $0, 0 as NSNumber) } }
            + dockKeys.map { (dock, $0, false as NSNumber) }
    }

    private static func restartDock() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["-u", NSUserName(), "Dock"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
    }

    static var backupPath: String {
        return NSString(string: "~/.config/calmtile/gestures-backup.plist").expandingTildeInPath
    }

    static var hasBackup: Bool { return FileManager.default.fileExists(atPath: backupPath) }

    private static func read(_ key: String, _ domain: String) -> Any? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    private static func write(_ key: String, _ domain: String, _ value: Any?) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    /// Back up (once), then set every four-finger gesture to 0 (off). Idempotent.
    static func disable() {
        if !hasBackup {
            // "domain/key" -> original value; a key that was not set is left out and removed again on restore.
            var saved = [String: Any]()
            for t in targets { if let v = read(t.key, t.domain) { saved["\(t.domain)/\(t.key)"] = v } }
            do {
                try FileManager.default.createDirectory(atPath: (backupPath as NSString).deletingLastPathComponent,
                                                        withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: saved, format: .xml, options: 0)
                try data.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
            } catch {
                Log.write("gestures: cannot write backup, leaving the trackpad alone")
                return
            }
        }
        var changed = false
        for t in targets {
            if (read(t.key, t.domain) as? NSNumber) != t.off { changed = true; write(t.key, t.domain, t.off) }
        }
        if changed { restartDock() }
        Log.write("gestures: four-finger gestures off")
    }

    /// Put the original values back (or remove the keys that were not set) and drop the backup.
    static func restore() {
        guard hasBackup else { return }
        guard let data = FileManager.default.contents(atPath: backupPath),
              let saved = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            Log.write("gestures: backup unreadable, kept at \(backupPath)")
            return
        }
        for t in targets { write(t.key, t.domain, saved["\(t.domain)/\(t.key)"]) }
        restartDock()
        try? FileManager.default.removeItem(atPath: backupPath)
        Log.write("gestures: restored")
    }
}
