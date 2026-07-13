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
        contentLabel = userImage != nil ? (path as NSString).lastPathComponent : "falhou ao carregar imagem"
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
        contentLabel = "padrão de teste (régua)"
        rebuild()
    }

    var spanEnabled: Bool { config.spanEnabled }
    var bezelPoints: Double { config.bezelPoints }

    func setSpanEnabled(_ enabled: Bool) {
        guard config.spanEnabled != enabled else { return }
        config.spanEnabled = enabled
        ConfigStore.save(config)
        rebuild()
    }

    func setBezelPoints(_ points: Double) {
        let clamped = max(0, points)
        guard config.bezelPoints != clamped else { return }
        config.bezelPoints = clamped
        ConfigStore.save(config)
        rebuild()
    }

    // MARK: - Rebuild

    func rebuild() {
        let plan = CanvasMapper.plan(screens: NSScreen.screens,
                                     bezelPoints: CGFloat(config.bezelPoints),
                                     spanEnabled: config.spanEnabled)
        spanScreenCount = plan.spanScreenCount

        pump?.stop()
        pump = nil
        windows.forEach { $0.orderOut(nil) }
        windows = plan.mappings.map { WallpaperWindow(mapping: $0) }
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
                contentLabel = "padrão de teste (régua)"
            }
        case .video:
            contentLabel = config.mediaPath.map { ($0 as NSString).lastPathComponent } ?? "vídeo"
        case .test:
            contentLabel = "padrão de teste (régua)"
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
