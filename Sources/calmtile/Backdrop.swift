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
