import AppKit
import AVFoundation

/// A borderless, non-interactive window covering one physical screen, at the
/// desktop level (above the system wallpaper, below the icons). One per display.
final class WallpaperWindow: NSWindow {
    private let content: SpanContentView

    init(mapping: ScreenMapping) {
        content = SpanContentView(mapping: mapping)
        super.init(contentRect: mapping.screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        canHide = false
        animationBehavior = .none

        contentView = content
        setFrame(mapping.screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func render(_ image: CGImage) { content.showImage(image) }
    func enqueue(_ sampleBuffer: CMSampleBuffer) { content.enqueue(sampleBuffer) }
    func showOnScreen() { orderBack(nil) }
}
