// Draw the logo and write assets/logo.svg and assets/calmtile.icns from one list of tiles.
//
//   swift scripts/make-icon.swift      run it from the top of the repository after changing the tiles
//
// The logo is the dwindle layout itself: every tile splits the last one, and the newest is the warm one.
import AppKit

struct Tile { let x, y, w, h, radius: CGFloat; let color: String }

let canvas: CGFloat = 512
let body = Tile(x: 0, y: 0, w: 512, h: 512, radius: 112, color: "#12222b")
let tiles = [
    Tile(x: 80, y: 80, w: 168, h: 352, radius: 24, color: "#2c4a57"),
    Tile(x: 264, y: 80, w: 168, h: 168, radius: 22, color: "#3f6673"),
    Tile(x: 264, y: 264, w: 76, h: 168, radius: 16, color: "#5b8a92"),
    Tile(x: 356, y: 264, w: 76, h: 76, radius: 14, color: "#86b3b0"),
    Tile(x: 356, y: 356, w: 76, h: 76, radius: 14, color: "#f4c98f"),
]

func cgColor(_ hex: String) -> CGColor {
    let v = Int(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

let rects = ([body] + tiles).map {
    "<rect x=\"\(Int($0.x))\" y=\"\(Int($0.y))\" width=\"\(Int($0.w))\" height=\"\(Int($0.h))\" rx=\"\(Int($0.radius))\" fill=\"\($0.color)\"/>"
}
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 512 512\">\(rects.joined())</svg>\n"
try svg.write(toFile: "assets/logo.svg", atomically: true, encoding: .utf8)

/// A macOS icon keeps a margin around its body: 824 of 1024 points on Apple's grid.
func png(pixels: Int, to path: String) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let size = CGFloat(pixels), scale = size * 824 / 1024 / canvas, margin = size * 100 / 1024
    for t in [body] + tiles {
        // Core Graphics counts y from the bottom, the tiles from the top.
        let r = CGRect(x: margin + t.x * scale, y: size - margin - (t.y + t.h) * scale, width: t.w * scale, height: t.h * scale)
        ctx.setFillColor(cgColor(t.color))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: t.radius * scale, cornerHeight: t.radius * scale, transform: nil))
        ctx.fillPath()
    }
    let data = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let set = NSTemporaryDirectory() + "calmtile-\(ProcessInfo.processInfo.processIdentifier).iconset"
try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(atPath: set) }
for points in [16, 32, 128, 256, 512] {
    png(pixels: points, to: "\(set)/icon_\(points)x\(points).png")
    png(pixels: points * 2, to: "\(set)/icon_\(points)x\(points)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set, "-o", "assets/calmtile.icns"]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
