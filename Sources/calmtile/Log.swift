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
    /// Kept open in append mode: opening and closing the file for every line cost more than the line itself, and
    /// the one-shot helpers append to the same file. Reopened when the file was moved away or deleted.
    private static var fd: Int32 = -1

    static func write(_ s: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(fmt.string(from: Date())) \(s)\n"
        if fd >= 0, access(url.path, F_OK) != 0 { close(fd); fd = -1 }
        if fd < 0 { fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644) }
        guard fd >= 0 else { return }
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    }
}
