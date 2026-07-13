import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// One wallpaper stored in the app's library folder.
struct WallpaperItem: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }

    var isVideo: Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie)) ?? false
    }
}

/// Manages the on-disk wallpaper library at
/// ~/Library/Application Support/SpanWall/Wallpapers. Importing copies the file
/// in (so the original download can be deleted), and thumbnails are generated
/// and cached in memory.
final class WallpaperLibrary: ObservableObject {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SpanWall/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Published private(set) var items: [WallpaperItem] = []
    private var thumbnailCache: [String: NSImage] = [:]

    init() { reload() }

    func reload() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        items = files
            .filter { isSupported($0) }
            .sorted { modDate($0) > modDate($1) }
            .map { WallpaperItem(url: $0) }
    }

    private func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .image)
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Copy a file into the library (unique name). Returns the imported item.
    @discardableResult
    func `import`(from source: URL) -> WallpaperItem? {
        let dest = uniqueDestination(for: source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            NSLog("SpanWall: import failed: \(error.localizedDescription)")
            return nil
        }
        reload()
        return items.first { $0.url.lastPathComponent == dest.lastPathComponent }
    }

    func delete(_ item: WallpaperItem) {
        try? FileManager.default.removeItem(at: item.url)
        thumbnailCache[item.id] = nil
        reload()
    }

    func contains(path: String?) -> Bool {
        guard let path else { return false }
        return URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL == Self.folder.standardizedFileURL
    }

    private func uniqueDestination(for filename: String) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = Self.folder.appendingPathComponent(filename)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = Self.folder.appendingPathComponent("\(name) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: - Thumbnails

    func thumbnail(for item: WallpaperItem) -> NSImage? {
        if let cached = thumbnailCache[item.id] { return cached }
        let image = item.isVideo ? videoThumbnail(item.url) : imageThumbnail(item.url)
        if let image { thumbnailCache[item.id] = image }
        return image
    }

    private func imageThumbnail(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func videoThumbnail(_ url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else {
            // fall back to the first frame
            guard let first = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
            return NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height))
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
