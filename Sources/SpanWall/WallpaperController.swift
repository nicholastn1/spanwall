import AppKit

/// Builds one `WallpaperWindow` per physical screen and drives its content: a
/// static image / ruler test pattern (canvas-sized, offset to each screen's
/// slice), or a spanned video handled by a `SyncedVideo` (one player per window,
/// shared clock).
final class WallpaperController {
    private var windows: [WallpaperWindow] = []
    private var observer: NSObjectProtocol?
    private var config = ConfigStore.load()

    private var userImage: CGImage?
    private var pump: VideoPump?

    // Lifecycle / power: pause the pump when the wallpaper isn't worth rendering.
    private var screensAsleep = false
    private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lifecycleObservers: [Any] = []

    var onScreensChanged: (() -> Void)?

    var screenCount: Int { NSScreen.screens.count }
    private(set) var spanScreenCount = 0
    private(set) var contentLabel = "—"

    func start() {
        if CommandLine.arguments.count > 1, !CommandLine.arguments[1].hasPrefix("-") {
            applyOverride(path: CommandLine.arguments[1])
        } else {
            loadConfigured()
        }
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
            self?.onScreensChanged?()
        }
        setUpLifecycleObservers()
    }

    // MARK: - Lifecycle / power (pause when not visible)

    private func setUpLifecycleObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        lifecycleObservers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true; self?.updateRenderState()
        })
        lifecycleObservers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false; self?.updateRenderState()
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRenderState()
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled; self?.updateRenderState()
        })
    }

    /// At least one wallpaper window is actually on screen (not fully covered).
    private var anyWindowVisible: Bool {
        windows.isEmpty || windows.contains { $0.occlusionState.contains(.visible) }
    }

    private func updateRenderState() {
        let shouldRender = !screensAsleep && !lowPowerMode && anyWindowVisible
        if shouldRender { pump?.resume() } else { pump?.pause() }
    }

    // MARK: - Content selection

    func chooseImage(path: String) {
        config.contentType = .image
        config.mediaPath = path
        ConfigStore.save(config)
        userImage = ImageLoader.load(path: path)
        contentLabel = userImage != nil ? (path as NSString).lastPathComponent : "failed to load image"
        rebuild()
    }

    func chooseVideo(path: String) {
        userImage = nil
        config.contentType = .video
        config.mediaPath = path
        ConfigStore.save(config)
        contentLabel = (path as NSString).lastPathComponent
        rebuild()
    }

    func useTestPattern() {
        userImage = nil
        config.contentType = .test
        config.mediaPath = nil
        ConfigStore.save(config)
        contentLabel = "test pattern (ruler)"
        rebuild()
    }

    var spanEnabled: Bool { config.spanEnabled }
    var bezelMillimeters: Double { config.bezelMillimeters }
    var fit: ContentFit { config.fit }
    var currentMediaPath: String? { config.mediaPath }

    /// Apply a library item as the active wallpaper.
    func apply(_ item: WallpaperItem) {
        if item.isVideo { chooseVideo(path: item.url.path) }
        else { chooseImage(path: item.url.path) }
    }

    func setFit(_ fit: ContentFit) {
        guard config.fit != fit else { return }
        config.fit = fit
        ConfigStore.save(config)
        rebuild()
    }

    func setSpanEnabled(_ enabled: Bool) {
        guard config.spanEnabled != enabled else { return }
        config.spanEnabled = enabled
        ConfigStore.save(config)
        rebuild()
    }

    /// Set the physical bezel gap (millimeters). `persist == false` is the live-drag
    /// path: it re-offsets the existing windows in place (no window/pump teardown) so
    /// the seam moves as the user drags. `persist == true` also writes it to disk.
    func setBezelMillimeters(_ mm: Double, persist: Bool) {
        let clamped = max(0, mm)
        if config.bezelMillimeters == clamped && !persist { return }
        config.bezelMillimeters = clamped
        if persist { ConfigStore.save(config) }
        applyBezelLive()
    }

    private func applyBezelLive() {
        let plan = CanvasMapper.plan(screens: NSScreen.screens,
                                     bezelMillimeters: CGFloat(config.bezelMillimeters),
                                     spanEnabled: config.spanEnabled)
        spanScreenCount = plan.spanScreenCount
        guard windows.count == plan.mappings.count else { rebuild(); return }
        for (w, m) in zip(windows, plan.mappings) { w.updateContentFrame(m.contentLayerFrame) }
        // Video keeps compositing via its continuous enqueue. For static content the
        // frame change already forces a recomposite, but we re-commit the image too so
        // a desktop-level window can't skip the repaint: the ruler must be regenerated
        // (it encodes seam positions), and a user image is simply re-set.
        switch config.contentType {
        case .test:
            let image = TestPattern.ruler(size: plan.canvasSize, seamsX: plan.seamsX)
            windows.forEach { $0.render(image) }
        case .image:
            if let userImage { windows.forEach { $0.render(userImage) } }
        case .video:
            break
        }
    }

    // MARK: - Rebuild

    func rebuild() {
        let plan = CanvasMapper.plan(screens: NSScreen.screens,
                                     bezelMillimeters: CGFloat(config.bezelMillimeters),
                                     spanEnabled: config.spanEnabled)
        spanScreenCount = plan.spanScreenCount

        pump?.stop()
        pump = nil
        windows.forEach { $0.orderOut(nil) }
        windows = plan.mappings.map { WallpaperWindow(mapping: $0, fit: config.fit) }
        windows.forEach { $0.showOnScreen() }

        if config.contentType == .video, let url = videoURL() {
            let p = VideoPump(url: url) { [weak self] sample in
                self?.windows.forEach { $0.enqueue(sample) }
            }
            p.start()
            pump = p
        } else {
            let image = userImage ?? TestPattern.ruler(size: plan.canvasSize, seamsX: plan.seamsX)
            windows.forEach { $0.render(image) }
        }

        updateRenderState()
    }

    private func videoURL() -> URL? {
        config.mediaPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    // MARK: - Config load / CLI override

    private func loadConfigured() {
        switch config.contentType {
        case .image:
            if let path = config.mediaPath, let image = ImageLoader.load(path: path) {
                userImage = image
                contentLabel = (path as NSString).lastPathComponent
            } else {
                config.contentType = .test
                contentLabel = "test pattern (ruler)"
            }
        case .video:
            contentLabel = config.mediaPath.map { ($0 as NSString).lastPathComponent } ?? "video"
        case .test:
            contentLabel = "test pattern (ruler)"
        }
    }

    /// A command-line path (handy for testing) overrides config without persisting.
    private func applyOverride(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "mpeg", "mpg"].contains(ext) {
            config.contentType = .video
            config.mediaPath = path
            contentLabel = (path as NSString).lastPathComponent + " (arg)"
        } else if let image = ImageLoader.load(path: path) {
            config.contentType = .image
            userImage = image
            contentLabel = (path as NSString).lastPathComponent + " (arg)"
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        lifecycleObservers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }
}
