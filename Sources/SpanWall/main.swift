import AppKit

// Entry point. A menu-bar *agent*: no Dock icon, no main window, no menu bar
// takeover. `.accessory` gives us that without needing an Info.plist/LSUIElement,
// which keeps this runnable as a bare `swift run` executable.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
