import AppKit
import AVFoundation

/// Renders this screen's slice. Static images go into a plain CALayer; video goes
/// into an `AVSampleBufferDisplayLayer`, into which we explicitly enqueue each
/// frame for immediate display — a push-based presentation path that doesn't need
/// the layer's internal display link (which is throttled in this desktop window)
/// and needs no geometry-wobble hack.
final class SpanContentView: NSView {
    private let imageLayer = CALayer()
    private let displayLayer = AVSampleBufferDisplayLayer()

    init(mapping: ScreenMapping, fit: ContentFit) {
        super.init(frame: CGRect(origin: .zero, size: mapping.screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        let f = mapping.contentLayerFrame
        let scale = mapping.screen.backingScaleFactor
        let (contentsGravity, videoGravity) = Self.gravities(for: fit)

        imageLayer.frame = f
        imageLayer.contentsGravity = contentsGravity
        imageLayer.contentsScale = scale
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        displayLayer.frame = f
        displayLayer.videoGravity = videoGravity
        displayLayer.masksToBounds = true
        displayLayer.isHidden = true
        layer?.addSublayer(displayLayer)
    }

    private static func gravities(for fit: ContentFit) -> (CALayerContentsGravity, AVLayerVideoGravity) {
        switch fit {
        case .fill:    return (.resizeAspectFill, .resizeAspectFill)
        case .fit:     return (.resizeAspect, .resizeAspect)
        case .stretch: return (.resize, .resize)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Re-position the canvas layer for this screen's slice without recreating the
    /// window or restarting playback — used for live bezel adjustment. Video keeps
    /// compositing via its continuous enqueue; a static image is re-committed so the
    /// desktop-level window repaints at the new offset.
    func updateContentFrame(_ frame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = frame
        displayLayer.frame = frame
        CATransaction.commit()
    }

    func showImage(_ image: CGImage) {
        displayLayer.isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.isHidden = false
        imageLayer.contents = image
        CATransaction.commit()
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if imageLayer.contents != nil { imageLayer.contents = nil }
        if imageLayer.isHidden == false { imageLayer.isHidden = true }
        if displayLayer.isHidden { displayLayer.isHidden = false }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sampleBuffer)
    }
}
