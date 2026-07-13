# SpanWall

A native macOS menu-bar app that spans **one wallpaper** — a static image or a
looping video — seamlessly across multiple monitors as a single ultrawide canvas.
(Apple dynamic `.heic` support is planned.)

> ⚠️ **Early alpha.** Built and validated on a specific 3-display macOS 26 setup.
> Expect rough edges; feedback welcome.

## Status

**Working: static image span + live video span** across multiple monitors.
- Fase 0 (plumbing) ✅ · Fase 1 (static image span) ✅ · Fase 2 (live video span) ✅
- Video is decoded once and pushed frame-by-frame to a per-display
  `AVSampleBufferDisplayLayer` (the same frame to every monitor → in sync,
  flicker-free). `AVPlayerLayer` is deliberately avoided — its hardware video path
  freezes in a background desktop window. See the plan doc for the full story.

Next: settings UI, launch-at-login, notarization, and Fase 3 (Apple dynamic `.heic`).

## Requirements

- macOS 13+ (developed on macOS 26)
- Swift toolchain (Command Line Tools is enough — no full Xcode required)
- Runs **unsandboxed** by design (drawing behind desktop icons + managing Spaces is
  not permitted under the App Sandbox).

## Build & run

```sh
make run       # build + package .app + launch (recommended)
make app       # build + package .build/SpanWall.app
make build     # compile the raw binary only
make release   # optimized build
```

Run it as the **`.app`** (`make run`): video playback is validated launched through
LaunchServices. Pick your wallpaper from the menu-bar icon (⬛ split-rectangle):
**Escolher vídeo…** or **Escolher imagem…** — the choice persists in
`~/Library/Application Support/SpanWall/config.json`. Quit from the menu
(▸ *Sair do SpanWall*) or `pkill -x SpanWall`.

> Build note: SwiftPM (`swift build`) is broken in this machine's Command Line
> Tools (`swift-package` crashes on a missing framework), so the Makefile compiles
> directly with `swiftc`. `Package.swift` is kept for when full Xcode is installed.

## Renaming the app

The name is centralized. To rename, change these and rebuild:

1. `name` and the target `name` in `Package.swift`
2. rename the `Sources/SpanWall/` directory to match the new target name
3. `AppInfo.displayName` in `Sources/SpanWall/AppInfo.swift`
4. `APP_NAME` in the `Makefile` (only used when packaging a `.app`)
