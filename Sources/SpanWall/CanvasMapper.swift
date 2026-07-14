import AppKit

extension NSScreen {
    /// This display's CoreGraphics ID, if resolvable from the device description.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Logical points per physical millimeter for this display, from its EDID
    /// physical size. `frame.width` is already in points, so this folds in the
    /// backing scale automatically. Falls back to a 27"-class ~4.3 pt/mm when the
    /// panel reports no physical size (e.g. some virtual or capture displays).
    var pointsPerMillimeter: CGFloat {
        guard let id = displayID else { return 4.3 }
        let mm = CGDisplayScreenSize(id)   // physical active area, millimeters
        guard mm.width > 1 else { return 4.3 }
        return frame.width / mm.width
    }
}

/// How one physical screen maps onto the shared virtual canvas.
struct ScreenMapping {
    let index: Int
    let screen: NSScreen
    let isInSpan: Bool
    /// Frame (in this screen's local window points) for a layer that represents the
    /// WHOLE canvas: canvas-sized and offset negatively so the window clips out just
    /// this screen's slice. For non-span screens it's simply the screen bounds.
    let contentLayerFrame: CGRect
}

struct CanvasPlan {
    let mappings: [ScreenMapping]
    let canvasSize: CGSize    // span-canvas size in points (render size for the test pattern)
    let seamsX: [CGFloat]     // internal seam x-positions (canvas points)
    let spanScreenCount: Int
}

/// Computes the virtual-canvas layout. The span group is the largest set of displays
/// sharing the same height, vertical origin, AND backing scale (a clean strip). Each
/// spanned screen gets a canvas-sized layer offset to its slice; other screens render
/// independently.
enum CanvasMapper {
    static func plan(screens: [NSScreen], bezelMillimeters: CGFloat, spanEnabled: Bool) -> CanvasPlan {
        guard spanEnabled, screens.count >= 2 else { return independentPlan(screens) }

        var buckets: [String: [NSScreen]] = [:]
        for s in screens {
            let key = "\(Int(s.frame.height))|\(Int(s.frame.origin.y))|\(s.backingScaleFactor)"
            buckets[key, default: []].append(s)
        }
        guard let span = buckets.values.max(by: { $0.count < $1.count }), span.count >= 2 else {
            return independentPlan(screens)
        }

        let ordered = span.sorted { $0.frame.origin.x < $1.frame.origin.x }
        let canvasHeight = ordered.map(\.frame.height).max() ?? 0

        var cursorX: CGFloat = 0
        var sampleOriginX: [ObjectIdentifier: CGFloat] = [:]
        var seams: [CGFloat] = []
        for (i, s) in ordered.enumerated() {
            sampleOriginX[ObjectIdentifier(s)] = cursorX
            cursorX += s.frame.width
            if i < ordered.count - 1 {
                // Convert the physical gap to points using the two displays bordering
                // this seam (average their DPI to stay correct even on mixed setups).
                let ppm = (s.pointsPerMillimeter + ordered[i + 1].pointsPerMillimeter) / 2
                let gap = bezelMillimeters * ppm
                seams.append(cursorX + gap / 2)
                cursorX += gap
            }
        }
        let canvasWidth = cursorX
        let spanSet = Set(span.map(ObjectIdentifier.init))

        let mappings = screens.enumerated().map { idx, screen -> ScreenMapping in
            if spanSet.contains(ObjectIdentifier(screen)) {
                let ox = sampleOriginX[ObjectIdentifier(screen)] ?? 0
                return ScreenMapping(index: idx, screen: screen, isInSpan: true,
                                     contentLayerFrame: CGRect(x: -ox, y: 0, width: canvasWidth, height: canvasHeight))
            } else {
                return ScreenMapping(index: idx, screen: screen, isInSpan: false,
                                     contentLayerFrame: CGRect(origin: .zero, size: screen.frame.size))
            }
        }

        return CanvasPlan(mappings: mappings,
                          canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
                          seamsX: seams,
                          spanScreenCount: span.count)
    }

    private static func independentPlan(_ screens: [NSScreen]) -> CanvasPlan {
        let mappings = screens.enumerated().map { idx, screen in
            ScreenMapping(index: idx, screen: screen, isInSpan: false,
                          contentLayerFrame: CGRect(origin: .zero, size: screen.frame.size))
        }
        let biggest = screens.map(\.frame.size).max(by: { $0.width < $1.width }) ?? CGSize(width: 1920, height: 1080)
        return CanvasPlan(mappings: mappings, canvasSize: biggest, seamsX: [], spanScreenCount: 0)
    }
}
