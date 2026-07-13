// swift-tools-version:5.9
import PackageDescription

// ── Renaming SpanWall ──────────────────────────────────────────────
// To rename the app you touch 3 places:
//   1. `name` + target `name` below
//   2. the Sources/SpanWall directory name (must match the target name)
//   3. AppInfo.displayName in Sources/SpanWall/AppInfo.swift
//   4. APP_NAME in the Makefile (only matters when packaging a .app)
// ───────────────────────────────────────────────────────────────────

let package = Package(
    name: "SpanWall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpanWall",
            path: "Sources/SpanWall"
        )
    ]
)
