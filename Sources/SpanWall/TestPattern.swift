import AppKit

/// Generates a ruler/grid image for verifying seam alignment. A continuous
/// centerline, full-canvas diagonals, and a yellow circle straddling each seam
/// make any misalignment across the monitor boundary instantly obvious.
enum TestPattern {
    static func ruler(size: CGSize, seamsX: [CGFloat]) -> CGImage {
        let w = max(16, Int(size.width.rounded()))
        let h = max(16, Int(size.height.rounded()))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let W = CGFloat(w), H = CGFloat(h)

        NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.06, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.16, blue: 0.22, alpha: 1)
        ])?.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 0)

        // Vertical + horizontal grid.
        for x in stride(from: CGFloat(0), through: W, by: 120) {
            let major = Int(x) % 480 == 0
            (major ? NSColor(white: 1, alpha: 0.35) : NSColor(white: 1, alpha: 0.12)).setStroke()
            let p = NSBezierPath(); p.lineWidth = major ? 2 : 1
            p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x, y: H)); p.stroke()
        }
        for y in stride(from: CGFloat(0), through: H, by: 120) {
            NSColor(white: 1, alpha: 0.10).setStroke()
            let p = NSBezierPath(); p.lineWidth = 1
            p.move(to: NSPoint(x: 0, y: y)); p.line(to: NSPoint(x: W, y: y)); p.stroke()
        }

        // Continuous centerline.
        NSColor.systemGreen.setStroke()
        let center = NSBezierPath(); center.lineWidth = 3
        center.move(to: NSPoint(x: 0, y: H / 2)); center.line(to: NSPoint(x: W, y: H / 2)); center.stroke()

        // Full-canvas diagonals (an X) — a kink at a seam reveals misalignment.
        NSColor(white: 1, alpha: 0.55).setStroke()
        for (a, b) in [(NSPoint(x: 0, y: 0), NSPoint(x: W, y: H)),
                       (NSPoint(x: 0, y: H), NSPoint(x: W, y: 0))] {
            let d = NSBezierPath(); d.lineWidth = 3
            d.move(to: a); d.line(to: b); d.stroke()
        }

        // Seam markers: red boundary line + yellow circle centered on the seam.
        for sx in seamsX {
            NSColor.systemRed.withAlphaComponent(0.9).setStroke()
            let line = NSBezierPath(); line.lineWidth = 4
            line.move(to: NSPoint(x: sx, y: 0)); line.line(to: NSPoint(x: sx, y: H)); line.stroke()

            NSColor.systemYellow.setStroke()
            let r = min(H * 0.42, 360)
            let circle = NSBezierPath(ovalIn: NSRect(x: sx - r, y: H / 2 - r, width: 2 * r, height: 2 * r))
            circle.lineWidth = 6; circle.stroke()
        }

        // X-coordinate labels.
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        for x in stride(from: CGFloat(0), through: W, by: 480) {
            ("x=\(Int(x))" as NSString).draw(at: NSPoint(x: x + 6, y: H - 34), withAttributes: labelAttrs)
        }

        // Title.
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        ("\(AppInfo.displayName) · \(AppInfo.phase) · canvas \(w)×\(h)" as NSString)
            .draw(at: NSPoint(x: 24, y: H / 2 + 40), withAttributes: titleAttrs)
        ("seam alignment test" as NSString)
            .draw(at: NSPoint(x: 24, y: H / 2 - 66), withAttributes: titleAttrs)

        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
