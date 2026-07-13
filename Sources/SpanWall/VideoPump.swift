import AppKit
import AVFoundation
import CoreVideo
import CoreMedia

/// Plays a looped, muted video and hands each decoded frame to a callback as a
/// `CMSampleBuffer` marked display-immediately. The controller enqueues that same
/// buffer into every screen's `AVSampleBufferDisplayLayer` — one decode, all
/// monitors in sync, pushed frame-by-frame (no AVPlayerLayer, no wobble).
final class VideoPump {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let onSample: (CMSampleBuffer) -> Void
    private var timer: Timer?
    private var endObserver: Any?
    private var held: CVPixelBuffer?

    init(url: URL, onSample: @escaping (CMSampleBuffer) -> Void) {
        self.onSample = onSample
        let item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ])
        item.add(output)

        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .none

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    func start() {
        player.play()
        startTimer()
    }

    /// Pause decoding + frame delivery (call when the wallpaper isn't visible).
    func pause() {
        timer?.invalidate()
        timer = nil
        player.pause()
    }

    /// Resume from a paused state. No-op if already running.
    func resume() {
        guard timer == nil else { return }
        player.play()
        startTimer()
    }

    private func startTimer() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 1.0 / 120.0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let host = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: host)
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let pb = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
              let sample = Self.makeSampleBuffer(from: pb)
        else { return }
        held = pb
        onSample(sample)
    }

    private static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDesc: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc) == noErr, let formatDesc else { return nil }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: .invalid,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescription: formatDesc, sampleTiming: &timing,
            sampleBufferOut: &sample) == noErr, let sample else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        held = nil
    }
}
