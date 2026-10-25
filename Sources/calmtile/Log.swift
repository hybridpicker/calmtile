import Foundation

/// Plain log in ~/Library/Logs/calmtile.log (window counts, actions, permission state; never titles).
enum Log {
    static let url = URL(fileURLWithPath: NSString(string: "~/Library/Logs/calmtile.log").expandingTildeInPath)
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static let debug = ProcessInfo.processInfo.environment["CALMTILE_DEBUG"] != nil
    private static let lock = NSLock()   // written from the main and the key tap thread

    static func write(_ s: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(fmt.string(from: Date())) \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}
