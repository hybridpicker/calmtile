import Foundation

/// The app was called hyprmac until October 2026. On the first start under the new name the config directory
/// is carried over once, and a login item of the old name is replaced by one for calmtile. Nothing else of the
/// old installation is touched; `~/Applications/hyprmac.app` can be deleted by hand.
enum Migration {
    private static let oldConfigDir = NSString(string: "~/.config/hyprmac").expandingTildeInPath
    private static let newConfigDir = NSString(string: "~/.config/calmtile").expandingTildeInPath

    static func run() {
        let fm = FileManager.default
        if fm.fileExists(atPath: oldConfigDir), !fm.fileExists(atPath: newConfigDir) {
            do {
                try fm.moveItem(atPath: oldConfigDir, toPath: newConfigDir)
                Log.write("migrated ~/.config/hyprmac to ~/.config/calmtile")
            } catch {
                Log.write("could not move ~/.config/hyprmac to ~/.config/calmtile: \(error.localizedDescription)")
            }
        }
        LoginItem.replaceOldItem(label: "local.hyprmac")
    }
}
