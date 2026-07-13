import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = WallpaperController()
    private var activityToken: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private lazy var settingsVM = SettingsViewModel(controller: controller)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent App Nap from suspending video playback while we run as a
        // background agent. Allows the system to still sleep normally.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "\(AppInfo.displayName) live wallpaper rendering")
        setUpStatusItem()
        controller.onScreensChanged = { [weak self] in self?.refreshMenu() }
        controller.start()
        refreshMenu()
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1",
                                   accessibilityDescription: AppInfo.displayName)
            button.image?.isTemplate = true
            if button.image == nil { button.title = "SW" }
        }
    }

    private func refreshMenu() {
        let menu = NSMenu()
        menu.addItem(header("\(AppInfo.displayName) \(AppInfo.version)"))
        menu.addItem(header("Telas: \(controller.screenCount)  ·  no span: \(controller.spanScreenCount)"))
        menu.addItem(header("Conteúdo: \(controller.contentLabel)"))
        menu.addItem(.separator())
        add(menu, "Configurações…", #selector(openSettings), key: ",")
        add(menu, "Escolher vídeo…", #selector(chooseVideo), key: "v")
        add(menu, "Escolher imagem…", #selector(chooseImage), key: "o")
        add(menu, "Usar padrão de teste (régua)", #selector(useTestPattern), key: "t")
        add(menu, "Recarregar", #selector(reload), key: "r")
        menu.addItem(.separator())
        let loginItem = add(menu, "Iniciar no login", #selector(toggleLaunchAtLogin), key: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        add(menu, "Sobre / GitHub…", #selector(openRepo), key: "")
        menu.addItem(.separator())
        add(menu, "Sair do \(AppInfo.displayName)", #selector(quit), key: "q")
        statusItem.menu = menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func chooseImage() {
        pickFile(types: [.image], message: "Escolha a imagem ultrawide para estender pelos monitores") { [weak self] url in
            self?.controller.chooseImage(path: url.path)
        }
    }

    @objc private func chooseVideo() {
        pickFile(types: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
                 message: "Escolha o vídeo para estender pelos monitores") { [weak self] url in
            self?.controller.chooseVideo(path: url.path)
        }
    }

    private func pickFile(types: [UTType], message: String, then handler: (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        if panel.runModal() == .OK, let url = panel.url {
            handler(url)
            refreshMenu()
        }
    }

    @objc private func useTestPattern() { controller.useTestPattern(); refreshMenu() }
    @objc private func reload() { controller.rebuild(); refreshMenu() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() }
            else { try service.register() }
        } catch {
            NSLog("SpanWall: launch-at-login toggle failed: \(error.localizedDescription)")
        }
        refreshMenu()
    }

    @objc private func openRepo() {
        if let url = URL(string: AppInfo.repoURL) { NSWorkspace.shared.open(url) }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(vm: settingsVM))
            let window = NSWindow(contentViewController: hosting)
            window.title = AppInfo.displayName
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsVM.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
