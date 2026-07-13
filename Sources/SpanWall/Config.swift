import Foundation

enum ContentType: String, Codable { case test, image, video }

/// Persisted settings. Lives in ~/Library/Application Support/SpanWall/config.json
/// (a plain file, so it works reliably for an unsandboxed bare executable that has
/// no bundle identifier for UserDefaults). Decoding is tolerant of missing keys so
/// old config files keep loading as the schema grows.
struct Config: Codable {
    var contentType: ContentType = .test
    var mediaPath: String? = nil
    var bezelPoints: Double = 0        // horizontal gap inserted between spanned displays
    var spanEnabled: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contentType = (try? c.decode(ContentType.self, forKey: .contentType)) ?? .test
        mediaPath = try? c.decode(String.self, forKey: .mediaPath)
        bezelPoints = (try? c.decode(Double.self, forKey: .bezelPoints)) ?? 0
        spanEnabled = (try? c.decode(Bool.self, forKey: .spanEnabled)) ?? true
    }
}

enum ConfigStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base
            .appendingPathComponent(AppInfo.displayName, isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }
        return cfg
    }

    static func save(_ config: Config) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL)
        }
    }
}
