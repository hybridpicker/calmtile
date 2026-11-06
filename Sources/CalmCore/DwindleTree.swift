import CoreGraphics

public typealias WindowID = UInt32

public enum Direction: String {
    case left, right, up, down
}

public enum Axis {
    /// first | second (side by side)
    case horizontal
    /// first over second
    case vertical
}

/// Binary space partition like Hyprland's "dwindle" layout: a new window splits the focused
/// one along its longer side; closing a window gives its space to its sibling.
public final class DwindleTree {
    final class Node {
        var window: WindowID?
        var first: Node?
        var second: Node?
        weak var parent: Node?
        var axis: Axis = .horizontal
        var ratio: CGFloat = 0.5

        init(window: WindowID) { self.window = window }
        init(first: Node, second: Node, axis: Axis) {
            self.first = first
            self.second = second
            self.axis = axis
        }
    }

    var root: Node?

    public init() {}

    public var isEmpty: Bool { return root == nil }

    /// Windows in tree order (left/top first).
    public var windows: [WindowID] {
        var out = [WindowID]()
        func walk(_ n: Node?) {
            guard let n = n else { return }
            if let w = n.window { out.append(w) } else { walk(n.first); walk(n.second) }
        }
        walk(root)
        return out
    }

    public func contains(_ id: WindowID) -> Bool { return leaf(of: id) != nil }

    func leaf(of id: WindowID) -> Node? {
        func find(_ n: Node?) -> Node? {
            guard let n = n else { return nil }
            if n.window == id { return n }
            return find(n.first) ?? find(n.second)
        }
        return find(root)
    }

    /// Minimum size an app insists on (learned by the engine); a split never gives a window less.
    public var minSize: (WindowID) -> CGSize = { _ in .zero }

    /// Smallest area `n` can be laid out in.
    func minimum(of n: Node, gap: CGFloat) -> CGSize {
        if let w = n.window { return minSize(w) }
        guard let a = n.first, let b = n.second else { return .zero }
        let ma = minimum(of: a, gap: gap), mb = minimum(of: b, gap: gap)
        switch n.axis {
        case .horizontal: return CGSize(width: ma.width + mb.width + gap, height: max(ma.height, mb.height))
        case .vertical: return CGSize(width: max(ma.width, mb.width), height: ma.height + mb.height + gap)
        }
    }

    public func minimum(gap: CGFloat) -> CGSize { return root.map { minimum(of: $0, gap: gap) } ?? .zero }

    /// Largest size a window can take (a window that cannot be resized, tiled at its own size); infinite for the
    /// rest. A split gives such a window no more than that, so its neighbours get the space it cannot use.
    public var maxSize: (WindowID) -> CGSize = { _ in CGSize(width: CGFloat.infinity, height: CGFloat.infinity) }
    /// False while no window has a maximum: the layout then skips that bookkeeping (it took the self-test's
    /// benchmark from 18 to 24 ms).
    public var hasMaxSizes: () -> Bool = { false }

    /// Split `r` into the two children's rectangles, the first one `extent` wide (or high). Edges are rounded to
    /// whole points, so every tile is integral, the halves never overlap and with no gap they meet exactly, even
    /// when `r` or `gap` is fractional (a Dock of 64.5 pt, a gap of 7.5).
    static func halves(of r: CGRect, axis: Axis, first extent: CGFloat, gap: CGFloat) -> (CGRect, CGRect) {
        switch axis {
        case .horizontal:
            let minX = r.minX.rounded(), maxX = r.maxX.rounded()
            let split = (r.minX + extent).rounded(), next = (r.minX + extent + gap).rounded()
            return (CGRect(x: minX, y: r.minY, width: max(0, split - minX), height: r.height),
                    CGRect(x: next, y: r.minY, width: max(0, maxX - next), height: r.height))
        case .vertical:
            let minY = r.minY.rounded(), maxY = r.maxY.rounded()
            let split = (r.minY + extent).rounded(), next = (r.minY + extent + gap).rounded()
            return (CGRect(x: r.minX, y: minY, width: r.width, height: max(0, split - minY)),
                    CGRect(x: r.minX, y: next, width: r.width, height: max(0, maxY - next)))
        }
    }

    /// What a window really takes of a tile of the given size, for a window that snaps to its own grid (Terminal:
    /// whole character cells); nil when nothing is known for that size. The rest of the tile goes to the neighbours.
    public var gridFit: (WindowID, CGSize) -> CGSize? = { _, _ in nil }
    /// False while no window is known to snap: the layout then runs once.
    public var hasGridFits: () -> Bool = { false }

    public func frames(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        let plain = layout(in: rect, gap: gap, slack: [:])
        guard hasGridFits() else { return plain }
        // Fits are known by the tile a window gets without them, which does not depend on what was given away before.
        var slack = [WindowID: CGSize]()
        for (w, f) in plain {
            if let fit = gridFit(w, f.size) { slack[w] = CGSize(width: f.width - fit.width, height: f.height - fit.height) }
        }
        return slack.isEmpty ? plain : layout(in: rect, gap: gap, slack: slack)
    }

    private func layout(in rect: CGRect, gap: CGFloat, slack: [WindowID: CGSize]) -> [WindowID: CGRect] {
        var out = [WindowID: CGRect]()
        /// How much narrower and lower a subtree can be. Beside a neighbour without slack the neighbour takes it, so
        /// nothing is left to pass on along the split; across the split the one with the most slack decides, because
        /// the other side can follow it.
        func slackOf(_ n: Node) -> CGSize {
            if let w = n.window { return slack[w] ?? .zero }
            guard let a = n.first, let b = n.second else { return .zero }
            let sa = slackOf(a), sb = slackOf(b)
            switch n.axis {
            case .horizontal: return CGSize(width: min(sa.width, sb.width), height: max(sa.height, sb.height))
            case .vertical: return CGSize(width: max(sa.width, sb.width), height: min(sa.height, sb.height))
            }
        }
        // Each split asks for the minimum of both of its subtrees; computed once per node instead of once per
        // ancestor (quadratic in a dwindle spiral, which is as deep as it has windows).
        var mins = [ObjectIdentifier: CGSize]()
        func minimum(of n: Node, gap: CGFloat) -> CGSize {
            if let m = mins[ObjectIdentifier(n)] { return m }
            let m: CGSize
            if let w = n.window { m = minSize(w) }
            else if let a = n.first, let b = n.second {
                let ma = minimum(of: a, gap: gap), mb = minimum(of: b, gap: gap)
                switch n.axis {
                case .horizontal: m = CGSize(width: ma.width + mb.width + gap, height: max(ma.height, mb.height))
                case .vertical: m = CGSize(width: max(ma.width, mb.width), height: ma.height + mb.height + gap)
                }
            } else { m = .zero }
            mins[ObjectIdentifier(n)] = m
            return m
        }
        var maxs = [ObjectIdentifier: CGSize]()
        func maximum(of n: Node) -> CGSize {
            if let m = maxs[ObjectIdentifier(n)] { return m }
            let m: CGSize
            if let w = n.window { m = maxSize(w) }
            else if let a = n.first, let b = n.second {
                let xa = maximum(of: a), xb = maximum(of: b)
                switch n.axis {
                case .horizontal: m = CGSize(width: xa.width + xb.width + gap, height: max(xa.height, xb.height))
                case .vertical: m = CGSize(width: max(xa.width, xb.width), height: xa.height + xb.height + gap)
                }
            } else { m = CGSize(width: CGFloat.infinity, height: CGFloat.infinity) }
            maxs[ObjectIdentifier(n)] = m
            return m
        }
        /// A side that cannot grow past its maximum leaves the rest to the other side, so a fixed-size window's
        /// neighbour gets everything it cannot use. When both sides have a maximum and space is left over, the first
        /// side's tile takes it and its window keeps its own size in the corner.
        func capped(_ e1: CGFloat, total: CGFloat, maxA: CGFloat, maxB: CGFloat) -> CGFloat {
            var e = e1
            if maxA.isFinite { e = min(e, maxA) }
            if maxB.isFinite { e = max(e, total - gap - maxB) }
            return e
        }
        let limited = hasMaxSizes()
        func place(_ n: Node, _ r: CGRect) {
            if let w = n.window, !limited { out[w] = r; return }
            if let w = n.window {
                // A fixed-size window gets a tile of its own size at the tile's top-left corner, never larger.
                let m = maxSize(w)
                out[w] = CGRect(x: r.minX, y: r.minY, width: min(r.width, m.width), height: min(r.height, m.height))
                return
            }
            guard let a = n.first, let b = n.second else { return }
            switch n.axis {
            case .horizontal:
                var w1 = ((r.width - gap) * n.ratio).rounded()
                let ma = minimum(of: a, gap: gap).width, mb = minimum(of: b, gap: gap).width
                if limited { w1 = capped(w1, total: r.width, maxA: maximum(of: a).width, maxB: maximum(of: b).width) }
                if !slack.isEmpty { w1 += slackOf(b).width - slackOf(a).width }
                if ma + mb + gap <= r.width {   // a minimum is only honoured when both sides can have theirs
                    w1 = min(max(w1, ma), r.width - gap - mb)
                }
                let (ra, rb) = DwindleTree.halves(of: r, axis: .horizontal, first: w1, gap: gap)
                place(a, ra)
                place(b, rb)
            case .vertical:
                var h1 = ((r.height - gap) * n.ratio).rounded()
                let ma = minimum(of: a, gap: gap).height, mb = minimum(of: b, gap: gap).height
                if limited { h1 = capped(h1, total: r.height, maxA: maximum(of: a).height, maxB: maximum(of: b).height) }
                if !slack.isEmpty { h1 += slackOf(b).height - slackOf(a).height }
                if ma + mb + gap <= r.height {
                    h1 = min(max(h1, ma), r.height - gap - mb)
                }
                let (ra, rb) = DwindleTree.halves(of: r, axis: .vertical, first: h1, gap: gap)
                place(a, ra)
                place(b, rb)
            }
        }
        if let root = root { place(root, rect) }
        return out
    }

    /// Insert `id` by splitting the leaf of `near` (or the last window) along its longer side.
    public func insert(_ id: WindowID, near: WindowID?, in rect: CGRect, gap: CGFloat) {
        guard !contains(id) else { return }
        let newLeaf = Node(window: id)
        guard let root = root else {
            self.root = newLeaf
            return
        }
        let frames = self.frames(in: rect, gap: gap)
        let target: Node
        if let n = near, let l = leaf(of: n) { target = l }
        else if let last = windows.last, let l = leaf(of: last) { target = l }
        else { target = root }
        let targetFrame = target.window.flatMap { frames[$0] } ?? rect
        var axis: Axis = targetFrame.width >= targetFrame.height ? .horizontal : .vertical
        // A fixed-size window keeps its size, so the new one can only have what that leaves free; split on the side of
        // the workspace where it leaves more. Its own tile is no guide, being cut to its size. Going by the window's
        // shape (a tall Simulator) put a new window into the 20 px under it, where it could not fit and ended up
        // floating as a strip.
        if let w = target.window {
            let m = maxSize(w)
            if m.width.isFinite || m.height.isFinite {
                let freeW = rect.width - min(rect.width, m.width)
                let freeH = rect.height - min(rect.height, m.height)
                axis = freeW >= freeH ? .horizontal : .vertical
            }
        }

        let oldParent = target.parent
        let split = Node(first: target, second: newLeaf, axis: axis)
        split.parent = oldParent
        if let p = oldParent {
            if p.first === target { p.first = split } else { p.second = split }
        } else {
            self.root = split
        }
        target.parent = split
        newLeaf.parent = split
    }

    public func remove(_ id: WindowID) {
        guard let l = leaf(of: id) else { return }
        guard let parent = l.parent else {
            root = nil
            return
        }
        let sibling = (parent.first === l) ? parent.second! : parent.first!
        let grand = parent.parent
        sibling.parent = grand
        if let g = grand {
            if g.first === parent { g.first = sibling } else { g.second = sibling }
        } else {
            root = sibling
        }
    }

    public func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(of: a), let lb = leaf(of: b) else { return }
        la.window = b
        lb.window = a
    }

    /// Flip the split that directly contains `id` (side by side <-> stacked).
    public func toggleSplit(of id: WindowID) {
        guard let p = leaf(of: id)?.parent else { return }
        p.axis = (p.axis == .horizontal) ? .vertical : .horizontal
    }

    /// Flip splits (side by side <-> stacked) until the minimum sizes fit `rect`, changing as few splits as possible.
    /// Returns false, leaving the tree as it was, when no combination fits. The order of the windows is kept.
    public func rearrangeToFit(in rect: CGRect, gap: CGFloat) -> Bool {
        var inner = [Node]()
        func collect(_ n: Node?) {
            guard let n = n, n.window == nil else { return }
            inner.append(n)
            collect(n.first); collect(n.second)
        }
        collect(root)
        guard !inner.isEmpty, inner.count <= 12 else { return false }
        func fits() -> Bool {
            let m = minimum(gap: gap)
            return m.width <= rect.width && m.height <= rect.height
        }
        func flip(_ i: Int) { inner[i].axis = inner[i].axis == .horizontal ? .vertical : .horizontal }
        // Subsets by number of flips: 1, 2, ... (at most 4095 trees of at most 12 splits).
        for count in 1...inner.count {
            var chosen = [Int]()
            func search(from i: Int) -> Bool {
                if chosen.count == count { return fits() }
                guard i < inner.count, inner.count - i >= count - chosen.count else { return false }
                flip(i); chosen.append(i)
                if search(from: i + 1) { return true }
                flip(i); chosen.removeLast()
                return search(from: i + 1)
            }
            if search(from: 0) { return true }
        }
        return false
    }

    /// Move the nearest divider of the matching axis in `direction`.
    public func moveDivider(of id: WindowID, direction: Direction, amount: CGFloat) {
        let want: Axis = (direction == .left || direction == .right) ? .horizontal : .vertical
        var n = leaf(of: id)
        while let cur = n, let p = cur.parent {
            if p.axis == want {
                let sign: CGFloat = (direction == .right || direction == .down) ? 1 : -1
                p.ratio = min(0.9, max(0.1, p.ratio + sign * amount))
                return
            }
            n = p
        }
    }

    /// AeroSpace `resize smart`: grow or shrink `id` along its nearest split, whichever side it is on.
    public func resizeSmart(of id: WindowID, grow: Bool, amount: CGFloat) {
        guard let leaf = leaf(of: id), let p = leaf.parent else { return }
        let isFirst = p.first === leaf
        let sign: CGFloat = (grow == isFirst) ? 1 : -1
        p.ratio = min(0.9, max(0.1, p.ratio + sign * amount))
    }

    /// Mouse resize: move the nearest horizontal and vertical dividers around `id` by pixels.
    /// `rect` and `gap` must match what `frames` was called with.
    public func dragDividers(of id: WindowID, dx: CGFloat, dy: CGFloat, in rect: CGRect, gap: CGFloat) {
        guard let target = leaf(of: id) else { return }
        var rects = [ObjectIdentifier: CGRect]()
        func walk(_ n: Node, _ r: CGRect) {
            rects[ObjectIdentifier(n)] = r
            guard let a = n.first, let b = n.second else { return }
            switch n.axis {
            case .horizontal:
                let (ra, rb) = DwindleTree.halves(of: r, axis: .horizontal, first: ((r.width - gap) * n.ratio).rounded(), gap: gap)
                walk(a, ra)
                walk(b, rb)
            case .vertical:
                let (ra, rb) = DwindleTree.halves(of: r, axis: .vertical, first: ((r.height - gap) * n.ratio).rounded(), gap: gap)
                walk(a, ra)
                walk(b, rb)
            }
        }
        if let root = root { walk(root, rect) }
        for axis in [Axis.horizontal, Axis.vertical] {
            let delta = axis == .horizontal ? dx : dy
            guard delta != 0 else { continue }
            var n = target.parent
            while let p = n {
                if p.axis == axis, let r = rects[ObjectIdentifier(p)] {
                    let extent = (axis == .horizontal ? r.width : r.height) - gap
                    if extent > 1 { p.ratio = min(0.9, max(0.1, p.ratio + delta / extent)) }
                    break
                }
                n = p.parent
            }
        }
    }
}
