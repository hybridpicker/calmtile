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

    public func frames(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        var out = [WindowID: CGRect]()
        func place(_ n: Node, _ r: CGRect) {
            if let w = n.window { out[w] = r; return }
            guard let a = n.first, let b = n.second else { return }
            switch n.axis {
            case .horizontal:
                let w1 = ((r.width - gap) * n.ratio).rounded()
                place(a, CGRect(x: r.minX, y: r.minY, width: w1, height: r.height))
                place(b, CGRect(x: r.minX + w1 + gap, y: r.minY, width: r.width - gap - w1, height: r.height))
            case .vertical:
                let h1 = ((r.height - gap) * n.ratio).rounded()
                place(a, CGRect(x: r.minX, y: r.minY, width: r.width, height: h1))
                place(b, CGRect(x: r.minX, y: r.minY + h1 + gap, width: r.width, height: r.height - gap - h1))
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
        let axis: Axis = targetFrame.width >= targetFrame.height ? .horizontal : .vertical

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
                let w1 = ((r.width - gap) * n.ratio).rounded()
                walk(a, CGRect(x: r.minX, y: r.minY, width: w1, height: r.height))
                walk(b, CGRect(x: r.minX + w1 + gap, y: r.minY, width: r.width - gap - w1, height: r.height))
            case .vertical:
                let h1 = ((r.height - gap) * n.ratio).rounded()
                walk(a, CGRect(x: r.minX, y: r.minY, width: r.width, height: h1))
                walk(b, CGRect(x: r.minX, y: r.minY + h1 + gap, width: r.width, height: r.height - gap - h1))
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
