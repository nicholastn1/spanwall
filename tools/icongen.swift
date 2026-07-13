import AppKit
import Foundation

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let S = CGFloat(size)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// Rounded-rect app-icon shape (transparent corners).
let margin: CGFloat = 80
let bg = NSRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
let bgPath = NSBezierPath(roundedRect: bg, xRadius: 205, yRadius: 205)
bgPath.addClip()
NSGradient(colors: [c(40, 38, 120), c(109, 40, 217), c(190, 60, 230)])!.draw(in: bg, angle: -45)

// Two monitor panels with a continuous panorama spanning the gap.
let panelW: CGFloat = 300, panelH: CGFloat = 300, gap: CGFloat = 44
let totalW = panelW * 2 + gap
let ox = (S - totalW) / 2
let oy = (S - panelH) / 2 + 12
let left = NSRect(x: ox, y: oy, width: panelW, height: panelH)
let right = NSRect(x: ox + panelW + gap, y: oy, width: panelW, height: panelH)
let union = NSRect(x: ox, y: oy, width: totalW, height: panelH)

func panorama(_ u: NSRect) {
    NSGradient(colors: [c(255, 186, 96), c(255, 108, 150), c(126, 72, 205)])!.draw(in: u, angle: 90)
    let r: CGFloat = 66
    let sun = NSBezierPath(ovalIn: NSRect(x: u.midX - r, y: u.minY + u.height*0.52 - r, width: 2*r, height: 2*r))
    c(255, 240, 150).setFill(); sun.fill()
    c(48, 24, 78, 0.92).setFill()
    let h = NSBezierPath()
    h.move(to: NSPoint(x: u.minX, y: u.minY))
    h.line(to: NSPoint(x: u.minX, y: u.minY + u.height*0.30))
    h.curve(to: NSPoint(x: u.midX, y: u.minY + u.height*0.20),
            controlPoint1: NSPoint(x: u.minX + u.width*0.16, y: u.minY + u.height*0.42),
            controlPoint2: NSPoint(x: u.minX + u.width*0.32, y: u.minY + u.height*0.16))
    h.curve(to: NSPoint(x: u.maxX, y: u.minY + u.height*0.32),
            controlPoint1: NSPoint(x: u.midX + u.width*0.20, y: u.minY + u.height*0.24),
            controlPoint2: NSPoint(x: u.maxX - u.width*0.14, y: u.minY + u.height*0.44))
    h.line(to: NSPoint(x: u.maxX, y: u.minY)); h.close(); h.fill()
}

for panel in [left, right] {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: panel, xRadius: 28, yRadius: 28).addClip()
    panorama(union)
    NSGraphicsContext.restoreGraphicsState()
    c(18, 14, 40).setStroke()
    let frame = NSBezierPath(roundedRect: panel, xRadius: 28, yRadius: 28)
    frame.lineWidth = 12; frame.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
