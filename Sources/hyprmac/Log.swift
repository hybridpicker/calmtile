import Foundation

/// Plain log in ~/Library/Logs/hyprmac.log (window counts, actions, permission state; never titles).
enum Log {
    static let url = URL(fileURLWithPath: NSString(string: "~/Library/Logs/hyprmac.log").expandingTildeInPath)
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ s: String) {
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
