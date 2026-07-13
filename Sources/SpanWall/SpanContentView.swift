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

    init(mapping: ScreenMapping) {
        super.init(frame: CGRect(origin: .zero, size: mapping.screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        let f = mapping.contentLayerFrame
        let scale = mapping.screen.backingScaleFactor

        imageLayer.frame = f
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.contentsScale = scale
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        displayLayer.frame = f
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.masksToBounds = true
        displayLayer.isHidden = true
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
