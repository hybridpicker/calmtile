import Foundation

/// Start at login through a per-user LaunchAgent (like AeroSpace's `start-at-login`). Opt-in: nothing is
/// installed until the menu item or `calmtile --install-login` asks for it; the same item removes it again.
enum LoginItem {
    static let label = "local.calmtile"

    static var plistPath: String {
        return NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath
    }

    static var isInstalled: Bool { return FileManager.default.fileExists(atPath: plistPath) }

    static func install() {
        let appPath = Bundle.main.bundlePath
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
            Log.write("login item installed")
        } catch {
            Log.write("login item: cannot write LaunchAgent")
        }
    }

    static func uninstall() {
        try? FileManager.default.removeItem(atPath: plistPath)
        Log.write("login item removed")
    }

    static func toggle() { isInstalled ? uninstall() : install() }

    /// A LaunchAgent left by the app's former name: unload and remove it, and install the current one in its place.
    static func replaceOldItem(label old: String) {
        let path = NSString(string: "~/Library/LaunchAgents/\(old).plist").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(old)"]
        try? p.run()
        p.waitUntilExit()
        try? FileManager.default.removeItem(atPath: path)
        Log.write("login item \(old) replaced by \(label)")
        install()
    }
}
