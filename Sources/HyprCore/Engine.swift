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

    /// A tile is never split below this size: the new window floats instead (0 turns the rule off).
    public var minTile = CGSize(width: 420, height: 280)

    public private(set) var monitors: [Monitor]
    public private(set) var focused: WindowID?
    public private(set) var currentWorkspace = 1
    public private(set) var previousWorkspace = 1

    private var workspaces = [Int: Workspace]()
    /// Minimum sizes apps turned out to insist on (window -> size, 0 = no limit on that axis).
    private var minSizes = [WindowID: CGSize]()
    /// Workspaces the user moved to another monitor by hand (workspace -> monitor).
    private var monitorOverride = [Int: Int]()
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
        } else if fits(into: ws) {
            insertTiled(id, into: ws)
        } else if let other = roomyWorkspace(after: ws) {
            // No room here without overlapping or squeezing: it opens on the next workspace with room.
            let target = ensure(other)
            home[id] = other
            insertTiled(id, into: target)
            target.lastFocused = id
            focused = id
            switchWorkspace(other)
            focused = id
            return
        } else {
            // Nowhere to go: a centred floating window.
            ws.floating.append(id)
            floatFrames[id] = centered(CGSize(width: monitors[ws.monitor].frame.width * 0.6,
                                              height: monitors[ws.monitor].frame.height * 0.7), on: ws.monitor)
        }
        ws.lastFocused = id
        focused = id
    }

    /// Turn a tiled window into a floating one at `frame` (title rules: playlists, inspectors, DevTools).
    public func makeFloating(_ id: WindowID, frame: CGRect) {
        guard let n = home[id], n != 0, let ws = workspaces[n], ws.tree.contains(id) else { return }
        ws.tree.remove(id)
        ws.floating.append(id)
        if ws.fullscreen == id { ws.fullscreen = nil }
        floatFrames[id] = frame
    }

    /// The app could not get as small as its tile. Remember the size it insists on so the neighbours make
    /// room; when even that cannot fit the workspace, it floats at that size instead.
    public func noteMinSize(_ id: WindowID, want: CGSize, got: CGSize) {
        guard let n = home[id], n != 0, let ws = workspaces[n], ws.tree.contains(id) else { return }
        let m = CGSize(width: got.width > want.width + 8 ? got.width : 0, height: got.height > want.height + 8 ? got.height : 0)
        guard m.width > 0 || m.height > 0 else { return }
        minSizes[id] = m
        let area = rect(of: ws), need = ws.tree.minimum(gap: gap)
        if need.width > area.width || need.height > area.height {
            // Cannot sit beside its neighbours without overlapping them: move it to a workspace with room.
            ws.tree.remove(id)
            if ws.lastFocused == id { ws.lastFocused = ws.tree.windows.last ?? ws.floating.last }
            if let other = roomyWorkspace(after: ws, needing: m) {
                let target = ensure(other)
                home[id] = other
                insertTiled(id, into: target)
                target.lastFocused = id
                switchWorkspace(other)
                focused = id
            } else {
                minSizes[id] = nil
                ws.floating.append(id)
                floatFrames[id] = centered(got, on: ws.monitor)
            }
        }
    }

    /// The next workspace (wrapping, same monitor) that can take one more window without overlap.
    private func roomyWorkspace(after ws: Workspace, needing m: CGSize = .zero) -> Int? {
        for step in 1...9 {
            let n = (ws.number - 1 + step) % 9 + 1
            guard n != ws.number, clampedMonitor(n) == ws.monitor else { continue }
            guard let cand = workspaces[n] else { return n }
            if cand.tree.windows.isEmpty { return n }
            let area = rect(of: cand)
            let need = cand.tree.minimum(gap: gap)
            if fits(into: cand), need.width + m.width + gap <= area.width { return n }
        }
        return nil
    }

    /// The app cannot get as small as its tile (minimum size): let it float at the size it insists on.
    public func floatTooBig(_ id: WindowID, actual: CGSize) {
        guard let n = home[id], n != 0, let ws = workspaces[n], ws.tree.contains(id) else { return }
        ws.tree.remove(id)
        ws.floating.append(id)
        if ws.fullscreen == id { ws.fullscreen = nil }
        floatFrames[id] = centered(actual, on: ws.monitor)
    }

    private func centered(_ size: CGSize, on monitor: Int) -> CGRect {
        let m = monitors[monitor].frame
        let w = min(size.width, m.width), h = min(size.height, m.height)
        return CGRect(x: (m.midX - w / 2).rounded(), y: (m.midY - h / 2).rounded(), width: w.rounded(), height: h.rounded())
    }

    /// Would splitting the tile next to the focus keep both halves at least `minTile`?
    private func fits(into ws: Workspace) -> Bool {
        guard minTile.width > 0 || minTile.height > 0, !ws.tree.windows.isEmpty else { return true }
        let frames = ws.tree.frames(in: rect(of: ws), gap: gap)
        let near = ws.lastFocused.flatMap { ws.tree.contains($0) ? $0 : nil } ?? ws.tree.windows.last!
        guard let f = frames[near] else { return true }
        if f.width >= f.height { return (f.width - gap) / 2 >= minTile.width }
        return (f.height - gap) / 2 >= minTile.height
    }

    public func windowGone(_ id: WindowID) {
        guard let n = home.removeValue(forKey: id) else { return }
        minSizes[id] = nil
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

    /// AeroSpace `move-workspace-to-monitor --wrap-around next`: the current workspace goes to the next monitor.
    public func moveWorkspaceToNextMonitor() {
        guard monitors.count > 1, let ws = workspaces[currentWorkspace] else { return }
        let old = ws.monitor
        let new = (old + 1) % monitors.count
        monitorOverride[ws.number] = new
        ws.monitor = new
        visible[new] = ws.number
        // The monitor it left shows another workspace that lives there, if any.
        visible[old] = workspaces.values.sorted { $0.number < $1.number }.first { $0.monitor == old && $0.number != ws.number }?.number
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

    public func resizeSmart(grow: Bool, amount: CGFloat = 0.05) {
        guard let id = focused, let ws = workspaces[currentWorkspace] else { return }
        ws.tree.resizeSmart(of: id, grow: grow, amount: amount)
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
                guard var f = floatFrames[id] else { continue }
                let area = monitors[ws.monitor].frame
                if !f.intersects(area) {   // its monitor was unplugged: bring it back into view
                    f.origin = CGPoint(x: (area.midX - f.width / 2).rounded(), y: (area.midY - f.height / 2).rounded())
                    floatFrames[id] = f
                }
                out[id] = .frame(f)
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
        return max(0, min(monitorOverride[n] ?? preferredMonitor(n), monitors.count - 1))
    }

    private func ensure(_ n: Int) -> Workspace {
        if let ws = workspaces[n] { return ws }
        let ws = Workspace(number: n, monitor: clampedMonitor(n))
        ws.tree.minSize = { [unowned self] id in self.minSizes[id] ?? .zero }
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
