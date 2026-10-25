import AppKit

/// A click-through outline drawn around the focused window.
final class BorderOverlay {
    private let window: NSWindow
    private let shape = CAShapeLayer()
    private var lastFrame: CGRect?

    var width: CGFloat = 3
    /// Draw inside the window edge (no room between tiles for an outside border).
    var inside = false
    var radius: CGFloat = 12
    var color: NSColor = NSColor(hex: "#89b4fa") ?? .systemBlue {
        didSet { shape.strokeColor = color.cgColor }
    }

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        view.layer?.addSublayer(shape)
        window.contentView = view
    }

    /// `frame` is in Accessibility coordinates (origin top-left of the main display, y down).
    func show(around frame: CGRect) {
        guard width > 0, let mainHeight = NSScreen.screens.first?.frame.height else { hide(); return }
        if frame == lastFrame, window.isVisible { return }
        lastFrame = frame
        let outer = inside ? frame : frame.insetBy(dx: -width, dy: -width)
        let rect = NSRect(x: outer.minX, y: mainHeight - outer.maxY, width: outer.width, height: outer.height)
        window.setFrame(rect, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = CGRect(origin: .zero, size: rect.size)
        // The stroke is centred on the path, so run it along the middle of the border band.
        let path = CGRect(origin: .zero, size: rect.size).insetBy(dx: width / 2, dy: width / 2)
        shape.lineWidth = width
        shape.path = CGPath(roundedRect: path, cornerWidth: radius + width / 2, cornerHeight: radius + width / 2, transform: nil)
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    func hide() {
        lastFrame = nil
        if window.isVisible { window.orderOut(nil) }
    }

    var isVisible: Bool { return window.isVisible }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
