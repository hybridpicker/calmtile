import AppKit

/// A theme-coloured layer under the tiled windows, only as large as the area they cover. macOS rounds every
/// window's corners and no app can change that; with this layer the notches where two tiles (or a tile and the screen
/// edge) meet show a dark seam instead of the wallpaper. An empty desktop has no layer and keeps its wallpaper.
/// Click-through, above the desktop icons, below every normal window.
final class BackdropOverlay {
    private let window: NSWindow
    private var lastFrame: CGRect?
    var color = NSColor.black { didSet { window.backgroundColor = color } }

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.backgroundColor = color
    }

    /// `frame` is in Accessibility coordinates (origin top-left of the main display, y down).
    func show(over frame: CGRect) {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { hide(); return }
        if frame == lastFrame, window.isVisible { return }
        lastFrame = frame
        window.setFrame(NSRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height), display: false)
        window.orderFrontRegardless()
    }

    func hide() {
        lastFrame = nil
        if window.isVisible { window.orderOut(nil) }
    }
}

/// A solid colour behind the menu bar of the main display (`menuBarBackground`). Since macOS 26 the menu bar has no
/// background of its own and shows the wallpaper through it; this layer, on the desktop's level, sits under the menu
/// bar so it reads on one calm colour instead. Click-through; gone while the menu bar is set to hide.
final class MenuBarStrip {
    private let window: NSWindow
    private var lastFrame: NSRect?
    var color = NSColor.black { didSet { window.backgroundColor = color } }

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.backgroundColor = color
    }

    /// Covers the strip the menu bar keeps out of the main display's usable area; hides when there is none.
    func update(enabled: Bool) {
        guard enabled, let main = NSScreen.screens.first else { hide(); return }
        let height = main.frame.maxY - main.visibleFrame.maxY
        guard height > 0 else { hide(); return }
        let frame = NSRect(x: main.frame.minX, y: main.frame.maxY - height, width: main.frame.width, height: height)
        if frame == lastFrame, window.isVisible { return }
        lastFrame = frame
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
    }

    func hide() {
        lastFrame = nil
        if window.isVisible { window.orderOut(nil) }
    }
}

/// Black corners over the tiles (`cornerMasks`). The backdrop lies under every window, so it only shows where a
/// window leaves its rounded corner see-through; an app that paints that corner itself (GTK 4 draws its own frame)
/// keeps a light patch there. These small click-through panels sit just above normal windows at each corner of each
/// tile and cover what lies outside a quarter circle of `radius`, so every corner reads in the backdrop's colour.
/// A corner that another window lies over is left uncovered, or the mask would cut into that window.
final class CornerMasks {
    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private var panels = [NSWindow]()
    private var lastKey = [String]()
    var color = NSColor.black {
        didSet { for p in panels { (p.contentView as? MaskView)?.color = color } }
    }

    /// `corners` in Accessibility coordinates (origin top-left of the main display, y down): the tile corner point
    /// and which corner of its tile it is.
    func show(_ corners: [(point: CGPoint, corner: Corner)], radius: CGFloat) {
        guard let mainHeight = NSScreen.screens.first?.frame.height, radius > 0 else { hide(); return }
        let key = corners.map { "\($0.point.x),\($0.point.y),\($0.corner),\(radius)" }
        if key == lastKey, panels.prefix(corners.count).allSatisfy({ $0.isVisible }) { return }
        lastKey = key
        while panels.count < corners.count { panels.append(CornerMasks.makePanel(color: color)) }
        for (i, c) in corners.enumerated() {
            let p = panels[i]
            let x = (c.corner == .topLeft || c.corner == .bottomLeft) ? c.point.x : c.point.x - radius
            let yTop = (c.corner == .topLeft || c.corner == .topRight) ? c.point.y : c.point.y - radius
            p.setFrame(NSRect(x: x, y: mainHeight - yTop - radius, width: radius, height: radius), display: false)
            (p.contentView as? MaskView)?.corner = c.corner
            p.contentView?.needsDisplay = true
            p.orderFrontRegardless()
        }
        for p in panels.dropFirst(corners.count) where p.isVisible { p.orderOut(nil) }
    }

    func hide() {
        lastKey = []
        for p in panels where p.isVisible { p.orderOut(nil) }
    }

    private static func makePanel(color: NSColor) -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        // Over the apps' windows, under their menus, popovers and tooltips. Hidden by Mission Control (transient).
        w.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let v = MaskView()
        v.color = color
        w.contentView = v
        return w
    }

    /// The square minus a quarter circle centred on the corner opposite the tile corner.
    private final class MaskView: NSView {
        var color = NSColor.black { didSet { needsDisplay = true } }
        var corner = Corner.topLeft

        override func draw(_ dirtyRect: NSRect) {
            let b = bounds
            let r = b.width
            // AppKit's y goes up: the tile's top corners are this view's top (maxY).
            let cx: CGFloat = (corner == .topLeft || corner == .bottomLeft) ? b.maxX : b.minX
            let cy: CGFloat = (corner == .topLeft || corner == .topRight) ? b.minY : b.maxY
            let path = NSBezierPath(rect: b)
            path.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)))
            path.windingRule = .evenOdd
            color.setFill()
            path.fill()
        }
    }
}
