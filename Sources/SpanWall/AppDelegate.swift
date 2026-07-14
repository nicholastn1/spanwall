import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = WallpaperController()
    private let library = WallpaperLibrary()
    private var activityToken: NSObjectProtocol?
    private var mainWindow: NSWindow?
    private lazy var mainVM = MainViewModel(controller: controller, library: library)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent App Nap from suspending video playback while we run as a
        // background agent. Allows the system to still sleep normally.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "\(AppInfo.displayName) live wallpaper rendering")
        setUpStatusItem()
        controller.onScreensChanged = { [weak self] in
            self?.refreshMenu()
            self?.mainVM.refresh()
        }
        controller.start()
        refreshMenu()
        if CommandLine.arguments.contains("--window") { openMainWindow() }
        if CommandLine.arguments.contains("--settings") { mainVM.section = .settings }
    }

    // MARK: - Menu bar (quick actions only; everything else lives in the window)

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
        menu.addItem(header("Content: \(controller.contentLabel)"))
        menu.addItem(.separator())
        add(menu, "Open SpanWall…", #selector(openMainWindow), key: "o")
        add(menu, "Reload", #selector(reload), key: "r")
        menu.addItem(.separator())
        add(menu, "Quit \(AppInfo.displayName)", #selector(quit), key: "q")
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

    @objc private func openMainWindow() {
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: MainWindowView(vm: mainVM))
            hosting.sizingOptions = []   // don't resize the window to each section's content
            let window = NSWindow(contentViewController: hosting)
            window.title = AppInfo.displayName
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 840, height: 540))
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        mainVM.refresh()
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func reload() { controller.rebuild(); refreshMenu() }
    @objc private func quit() { NSApp.terminate(nil) }
}
