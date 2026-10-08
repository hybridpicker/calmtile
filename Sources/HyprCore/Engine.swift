import CoreGraphics

public enum Placement: Equatable {
    case frame(CGRect)
    /// Parked off the corner of this monitor (inactive workspace).
    case hidden(monitor: Int)
}

public struct Monitor: Equatable {
    public var id: Int
    public var frame: CGRect
    public init(id: Int, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// Workspaces, focus and layout decisions. Knows nothing about macOS: windows are opaque ids,
/// frames are plain rectangles in whatever coordinate space the caller uses.
public final class Engine {
    final class Workspace {
        let number: Int
        var monitor: Int
        let tree = DwindleTree()
        var floating = [WindowID]()
        var fullscreen: WindowID?
        var lastFocused: WindowID?

        init(number: Int, monitor: Int) {
            self.number = number
            self.monitor = monitor
        }

        var all: [WindowID] { return tree.windows + floating }
    }

    public var gap: CGFloat = 8
    public var outerGap: CGFloat = 8
    /// Which monitor a workspace lives on (clamped to the monitors that exist).
    public var preferredMonitor: (Int) -> Int = { $0 <= 5 ? 0 : 1 }

    public private(set) var monitors: [Monitor]
    public private(set) var focused: WindowID?
    public private(set) var currentWorkspace = 1
    public private(set) var previousWorkspace = 1

    private var workspaces = [Int: Workspace]()
    private var visible = [Int: Int]()          // monitor id -> workspace number
    private var home = [WindowID: Int]()        // window -> workspace number
    private var floatFrames = [WindowID: CGRect]()
    /// The scratchpad: windows that belong to no workspace (home == 0) and pop up on demand.
    private var scratch = [WindowID]()
    public private(set) var scratchShown: WindowID?

    public init(monitors: [Monitor]) {
        self.monitors = monitors.isEmpty ? [Monitor(id: 0, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))] : monitors
        _ = ensure(1)
        visible[workspaces[1]!.monitor] = 1
    }

    // MARK: - Queries

    public func workspaceOf(_ id: WindowID) -> Int? { return home[id] }
    public func isFloating(_ id: WindowID) -> Bool {
        if home[id] == 0 { return true }
        guard let n = home[id], let ws = workspaces[n] else { return false }
        return ws.floating.contains(id)
    }
    public var currentFullscreen: WindowID? { return workspaces[currentWorkspace]?.fullscreen }
    public func visibleWorkspace(on monitor: Int) -> Int? { return visible[monitor] }
    public var windowCount: Int { return home.count }
    public var workspaceNumbers: [Int] { return workspaces.keys.sorted() }
    /// Windows of a workspace in tree order, floating ones last.
    public func windows(in n: Int) -> [WindowID] { return workspaces[n]?.all ?? [] }
    public var scratchpadWindows: [WindowID] { return scratch }

    /// Tiled frames of the current workspace (what directional focus navigates).
    public func tiledFrames() -> [WindowID: CGRect] {
        guard let ws = workspaces[currentWorkspace] else { return [:] }
        return ws.tree.frames(in: rect(of: ws), gap: gap)
    }

    // MARK: - Events from the platform

    public func setMonitors(_ new: [Monitor]) {
        guard !new.isEmpty, new != monitors else { return }
        monitors = new
        visible = [:]
        for ws in workspaces.values.sorted(by: { $0.number < $1.number }) {
            ws.monitor = clampedMonitor(ws.number)
            if visible[ws.monitor] == nil { visible[ws.monitor] = ws.number }
        }
        if let cur = workspaces[currentWorkspace] { visible[cur.monitor] = cur.number }
    }

    public func windowAppeared(_ id: WindowID, floating: Bool, frame: CGRect? = nil) {
        guard home[id] == nil else { return }
        let ws = ensure(currentWorkspace)
        home[id] = ws.number
        if floating {
            ws.floating.append(id)
            if let f = frame { floatFrames[id] = f }
        } else {
            insertTiled(id, into: ws)
        }
        ws.lastFocused = id
        focused = id
    }

    public func windowGone(_ id: WindowID) {
        guard let n = home.removeValue(forKey: id) else { return }
        if n == 0 {
            scratch.removeAll { $0 == id }
            floatFrames[id] = nil
            if scratchShown == id { scratchShown = nil }
            if focused == id { focused = workspaces[currentWorkspace]?.lastFocused }
            return
        }
        guard let ws = workspaces[n] else { return }
        detach(id, from: ws)
        floatFrames[id] = nil
        if focused == id { focused = (n == currentWorkspace) ? ws.lastFocused : nil }
    }

    /// The OS reports which window has focus (click, app switch).
    public func setFocused(_ id: WindowID) {
        if home[id] == 0 {
            if scratchShown == id { focused = id }   // a hidden scratchpad window cannot take focus
            return
        }
        guard let n = home[id], let ws = workspaces[n], visible[ws.monitor] == n else { return }
        focused = id
        ws.lastFocused = id
        if currentWorkspace != n {
            previousWorkspace = currentWorkspace
            currentWorkspace = n
        }
    }

    /// Remember where a floating window actually is, so it returns there after a workspace switch.
    public func noteFloatFrame(_ id: WindowID, _ frame: CGRect) {
        guard isFloating(id) else { return }
        floatFrames[id] = frame
    }

    // MARK: - Commands

    public func switchWorkspace(_ n: Int) {
        guard n != currentWorkspace || workspaces[n] == nil else { return }
        let ws = ensure(n)
        previousWorkspace = currentWorkspace
        currentWorkspace = n
        visible[ws.monitor] = n
        focused = ws.lastFocused ?? ws.tree.windows.first ?? ws.floating.first
    }

    /// Bring a window into view and focus it, switching workspace if it lives on another one.
    public func activate(_ id: WindowID) {
        if home[id] == 0 {
            scratch.removeAll { $0 == id }
            scratch.append(id)
            scratchShown = id
            focused = id
            return
        }
        guard let n = home[id], let ws = workspaces[n] else { return }
        switchWorkspace(n)
        focused = id
        ws.lastFocused = id
    }

    public func backAndForth() { switchWorkspace(previousWorkspace) }

    public func moveFocused(toWorkspace n: Int) {
        if let id = focused, home[id] == 0 { unscratch(id, to: n); return }
        guard let id = focused, let from = home[id], let src = workspaces[from], n != from else { return }
        let wasFloating = src.floating.contains(id)
        detach(id, from: src)
        let dest = ensure(n)
        if wasFloating { dest.floating.append(id) } else { insertTiled(id, into: dest) }
        home[id] = n
        dest.lastFocused = id
        focused = src.lastFocused
    }

    // MARK: - Scratchpad

    /// Put a window into the scratchpad (hidden, floating, centred when shown). `show` pops it up at once.
    public func moveToScratchpad(_ id: WindowID, show: Bool = false) {
        guard let n = home[id], n != 0, let src = workspaces[n] else { return }
        let wasFocused = focused == id
        detach(id, from: src)
        scratch.append(id)
        home[id] = 0
        floatFrames[id] = scratchFrame()
        if wasFocused { focused = src.lastFocused }
        if show {
            scratchShown = id
            focused = id
        }
    }

    /// The focused window goes to the scratchpad; a scratchpad window comes back to this workspace.
    public func moveFocusedToScratchpad() {
        guard let id = focused, let n = home[id] else { return }
        if n == 0 { unscratch(id, to: currentWorkspace) } else { moveToScratchpad(id) }
    }

    /// Show the most recent scratchpad window, or hide it again. False when the scratchpad is empty.
    @discardableResult
    public func toggleScratchpad() -> Bool {
        if scratchShown != nil {
            scratchShown = nil
            focused = workspaces[currentWorkspace]?.lastFocused
            return true
        }
        guard let id = scratch.last else { return false }
        scratchShown = id
        focused = id
        return true
    }

    private func unscratch(_ id: WindowID, to n: Int) {
        scratch.removeAll { $0 == id }
        if scratchShown == id { scratchShown = nil }
        let ws = ensure(n)
        ws.floating.append(id)
        home[id] = n
        ws.lastFocused = id
        focused = (n == currentWorkspace) ? id : workspaces[currentWorkspace]?.lastFocused
    }

    private func scratchFrame() -> CGRect {
        let m = monitors[min(workspaces[currentWorkspace]?.monitor ?? 0, monitors.count - 1)].frame
        let w = (m.width * 0.7).rounded()
        let h = (m.height * 0.6).rounded()
        return CGRect(x: (m.midX - w / 2).rounded(), y: (m.midY - h / 2).rounded(), width: w, height: h)
    }

    @discardableResult
    public func focus(_ d: Direction) -> Bool {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return false }
        guard let target = Engine.neighbor(of: id, in: tiledFrames(), direction: d) else { return false }
        focused = target
        ws.lastFocused = target
        return true
    }

    /// Swap the focused window with its neighbour in `d`.
    public func swap(_ d: Direction) {
        guard let id = focused, let ws = workspaces[currentWorkspace],
              let other = Engine.neighbor(of: id, in: tiledFrames(), direction: d) else { return }
        ws.tree.swap(id, other)
    }

    public func resize(_ d: Direction, amount: CGFloat = 0.05) {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return }
        ws.tree.moveDivider(of: id, direction: d, amount: amount)
    }

    /// Exchange two tiled windows of the current workspace (mouse drop).
    public func swapWindows(_ a: WindowID, _ b: WindowID) {
        guard let ws = workspaces[currentWorkspace] else { return }
        ws.tree.swap(a, b)
    }

    /// Mouse resize of the focused tiled window: dividers follow the pointer by `dx`/`dy` pixels.
    public func resizeBy(dx: CGFloat, dy: CGFloat) {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return }
        ws.tree.dragDividers(of: id, dx: dx, dy: dy, in: rect(of: ws), gap: gap)
    }

    public func toggleSplit() {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return }
        ws.tree.toggleSplit(of: id)
    }

    public func toggleFloating() {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return }
        if let i = ws.floating.firstIndex(of: id) {
            ws.floating.remove(at: i)
            floatFrames[id] = nil
            insertTiled(id, into: ws)
        } else if let f = tiledFrames()[id] {
            ws.tree.remove(id)
            ws.floating.append(id)
            floatFrames[id] = f.insetBy(dx: 24, dy: 24)
            if ws.fullscreen == id { ws.fullscreen = nil }
        }
    }

    public func toggleFullscreen() {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return }
        ws.fullscreen = (ws.fullscreen == id) ? nil : id
    }

    // MARK: - Result

    /// Where every known window should be. Floating windows without a known frame are left alone
    /// (absent from the result).
    public func plan() -> [WindowID: Placement] {
        var out = [WindowID: Placement]()
        for ws in workspaces.values {
            if visible[ws.monitor] != ws.number {
                for id in ws.all { out[id] = .hidden(monitor: ws.monitor) }
                continue
            }
            for (id, f) in ws.tree.frames(in: rect(of: ws), gap: gap) { out[id] = .frame(f) }
            for id in ws.floating {
                if let f = floatFrames[id] { out[id] = .frame(f) }
            }
            if let fs = ws.fullscreen, home[fs] != nil {
                out[fs] = .frame(monitors[ws.monitor].frame)
            }
        }
        let cur = min(workspaces[currentWorkspace]?.monitor ?? 0, monitors.count - 1)
        for id in scratch {
            if id == scratchShown, let f = floatFrames[id] { out[id] = .frame(f) } else { out[id] = .hidden(monitor: cur) }
        }
        return out
    }

    // MARK: - Helpers

    /// Nearest window in `d` that overlaps the focused one on the other axis.
    public static func neighbor(of id: WindowID, in frames: [WindowID: CGRect], direction d: Direction) -> WindowID? {
        guard let f = frames[id] else { return nil }
        var best: (id: WindowID, dist: CGFloat, overlap: CGFloat)?
        for (cid, c) in frames where cid != id {
            let dist: CGFloat
            let overlap: CGFloat
            switch d {
            case .left:
                dist = f.minX - c.maxX
                overlap = min(f.maxY, c.maxY) - max(f.minY, c.minY)
            case .right:
                dist = c.minX - f.maxX
                overlap = min(f.maxY, c.maxY) - max(f.minY, c.minY)
            case .up:
                dist = f.minY - c.maxY
                overlap = min(f.maxX, c.maxX) - max(f.minX, c.minX)
            case .down:
                dist = c.minY - f.maxY
                overlap = min(f.maxX, c.maxX) - max(f.minX, c.minX)
            }
            guard dist >= -1, overlap > 1 else { continue }
            if let b = best {
                if dist < b.dist - 0.5 || (abs(dist - b.dist) <= 0.5 && overlap > b.overlap) {
                    best = (cid, dist, overlap)
                }
            } else {
                best = (cid, dist, overlap)
            }
        }
        return best?.id
    }

    private func clampedMonitor(_ n: Int) -> Int {
        return max(0, min(preferredMonitor(n), monitors.count - 1))
    }

    private func ensure(_ n: Int) -> Workspace {
        if let ws = workspaces[n] { return ws }
        let ws = Workspace(number: n, monitor: clampedMonitor(n))
        workspaces[n] = ws
        if visible[ws.monitor] == nil { visible[ws.monitor] = n }
        return ws
    }

    private func rect(of ws: Workspace) -> CGRect {
        return monitors[ws.monitor].frame.insetBy(dx: outerGap, dy: outerGap)
    }

    private func insertTiled(_ id: WindowID, into ws: Workspace) {
        let near = ws.lastFocused.flatMap { ws.tree.contains($0) ? $0 : nil }
        ws.tree.insert(id, near: near, in: rect(of: ws), gap: gap)
    }

    private func detach(_ id: WindowID, from ws: Workspace) {
        ws.tree.remove(id)
        ws.floating.removeAll { $0 == id }
        if ws.fullscreen == id { ws.fullscreen = nil }
        if ws.lastFocused == id { ws.lastFocused = ws.tree.windows.last ?? ws.floating.last }
    }
}
