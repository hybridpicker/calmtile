import Foundation

/// Start at login through a per-user LaunchAgent (like AeroSpace's `start-at-login`). Opt-in: nothing is
/// installed until the menu item or `hyprmac --install-login` asks for it; the same item removes it again.
enum LoginItem {
    static let label = "local.hyprmac"

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
}
