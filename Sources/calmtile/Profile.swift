import Foundation
import QuartzCore

/// Tick profile for development (CALMTILE_DEBUG or CALMTILE_PROFILE): every 20 full ticks one log line with the
/// main thread's time per tick (p50/p95/max), time per phase, Accessibility and window server calls per tick,
/// notifications by kind, the slowest apps to list, and how long hotkeys waited for the main thread.
/// Numbers and bundle ids only, never titles. Everything runs on the main thread except `ax()`, `ws()` and
/// `listed()`, which the listing thread calls too and which are counted under a lock. A tick's time is the main
/// thread's share only: the wait for the listing thread in between does not count (see `suspendTick`).
enum Profile {
    static let on = Log.debug || ProcessInfo.processInfo.environment["CALMTILE_PROFILE"] != nil
    private static let every = 20

    private static let lock = NSLock()
    private static var axCalls = 0
    private static var wsCalls = 0

    private static var tickTimes = [Double]()
    private static var phases = [String: Double]()
    private static var phaseOrder = [String]()
    private static var notes = [String: Int]()
    private static var appListing = [String: Double]()
    private static var keyWaits = [Double]()
    private static var lateKeys = 0
    private static var requested = 0
    private static var windowStart = CACurrentMediaTime()
    private static var tickStart: CFTimeInterval = 0

    /// One Accessibility round trip (attribute read or write, action).
    @inline(__always) static func ax(_ n: Int = 1) {
        guard on else { return }
        lock.lock(); axCalls += n; lock.unlock()
    }

    /// One window server query.
    @inline(__always) static func ws(_ n: Int = 1) {
        guard on else { return }
        lock.lock(); wsCalls += n; lock.unlock()
    }

    /// Time `work` under `name` for the current tick.
    @discardableResult
    static func phase<T>(_ name: String, _ work: () -> T) -> T {
        guard on else { return work() }
        let t0 = CACurrentMediaTime()
        let r = work()
        add(name, CACurrentMediaTime() - t0)
        return r
    }

    static func add(_ name: String, _ dt: Double) {
        guard on else { return }
        if phases[name] == nil { phaseOrder.append(name) }
        phases[name, default: 0] += dt
    }

    static func note(_ kind: String, _ bundleID: String) {
        guard on else { return }
        notes["\(kind)@\(bundleID)", default: 0] += 1
    }

    static func listed(_ bundleID: String, _ dt: Double) {
        guard on else { return }
        lock.lock(); appListing[bundleID, default: 0] += dt; lock.unlock()
    }

    static func tickRequested() {
        guard on else { return }
        requested += 1
    }

    /// A hotkey reached the main thread `wait` seconds after the tap asked; `late` when the tap had given up.
    static func key(wait: Double, late: Bool) {
        guard on else { return }
        keyWaits.append(wait)
        if late { lateKeys += 1 }
    }

    private static var tickAccum: Double = 0

    static func beginTick() {
        guard on else { return }
        tickStart = CACurrentMediaTime()
        tickAccum = 0
    }

    /// The tick hands the listing to its thread: stop counting until `resumeTick`.
    static func suspendTick() {
        guard on, tickStart > 0 else { return }
        tickAccum += CACurrentMediaTime() - tickStart
        tickStart = 0
    }

    static func resumeTick() {
        guard on else { return }
        tickStart = CACurrentMediaTime()
    }

    /// Workspace shown when the line is written (lets a test find its way back without switching).
    static var workspace = 0

    static func endTick() {
        guard on, tickStart > 0 else { return }
        tickTimes.append(tickAccum + CACurrentMediaTime() - tickStart)
        tickStart = 0
        tickAccum = 0
        if tickTimes.count >= every { flush() }
    }

    private static func ms(_ s: Double) -> String { return String(format: "%.1f", s * 1000) }

    private static func flush() {
        let sorted = tickTimes.sorted()
        func pct(_ p: Double) -> Double { return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))] }
        let n = Double(tickTimes.count)
        lock.lock(); let ax = axCalls, wsc = wsCalls; axCalls = 0; wsCalls = 0; lock.unlock()
        let span = CACurrentMediaTime() - windowStart
        var line = "profile: workspace=\(workspace) ticks=\(tickTimes.count) in \(String(format: "%.1f", span)) s requested=\(requested)"
        line += " tick ms p50=\(ms(pct(0.5))) p95=\(ms(pct(0.95))) max=\(ms(sorted.last ?? 0))"
        line += " phase ms/tick " + phaseOrder.map { "\($0)=\(ms((phases[$0] ?? 0) / n))" }.joined(separator: " ")
        line += " ax/tick=\(Int((Double(ax) / n).rounded())) ws/tick=\(Int((Double(wsc) / n).rounded()))"
        lock.lock(); let listing = appListing; appListing.removeAll(); lock.unlock()
        let slow = listing.sorted { $0.value > $1.value }.prefix(3).filter { $0.value / n > 0.002 }
        if !slow.isEmpty { line += " list ms/tick " + slow.map { "\($0.key)=\(ms($0.value / n))" }.joined(separator: " ") }
        if !notes.isEmpty {
            line += " notes " + notes.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        if !keyWaits.isEmpty { line += " keys=\(keyWaits.count) wait max ms=\(ms(keyWaits.max() ?? 0)) late=\(lateKeys)" }
        Log.write(line)
        tickTimes.removeAll(keepingCapacity: true)
        phases.removeAll()
        phaseOrder.removeAll()
        notes.removeAll()
        keyWaits.removeAll()
        lateKeys = 0
        requested = 0
        windowStart = CACurrentMediaTime()
    }
}
