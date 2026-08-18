import Foundation

public enum PresetCatalogError: Error, LocalizedError {
    case directoryMissing
    case empty
    case decodeFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .directoryMissing: return "Preset directory was not found."
        case .empty: return "No presets were found."
        case .decodeFailed(let name, let error): return "Preset \(name) failed to decode: \(error.localizedDescription)"
        }
    }
}

public enum PresetCatalog {
    public static let expectedIDs = [
        "viral-hook",
        "cinematic-story",
        "product-demo",
        "faceless-facts",
        "luxury-brand",
        "youtube-short-news",
        "travel-vlog",
        "tutorial-steps",
        "listicle",
        "explainer",
        "storytime",
        "motivational",
        "podcast-clip",
        "news-roundup"
    ]

    public static func load(from directory: URL) throws -> [Preset] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if files.isEmpty { throw PresetCatalogError.empty }

        let decoder = JSONDecoder()
        var presets: [Preset] = []
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                presets.append(try decoder.decode(Preset.self, from: data))
            } catch {
                throw PresetCatalogError.decodeFailed(file.lastPathComponent, error)
            }
        }
        return presets.sorted { lhs, rhs in
            (expectedIDs.firstIndex(of: lhs.id) ?? 99) < (expectedIDs.firstIndex(of: rhs.id) ?? 99)
        }
    }

    public static func bundledDirectory() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "presets", withExtension: nil) {
            return url
        }
        if let url = Bundle.module.resourceURL?.appendingPathComponent("presets"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: "presets", withExtension: nil) {
            return url
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("presets"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return sourceTreeDirectory()
    }

    public static func loadBundled() throws -> [Preset] {
        if let dir = bundledDirectory() {
            return try load(from: dir)
        }
        throw PresetCatalogError.directoryMissing
    }

    public static func sourceTreeDirectory(file: String = #file) -> URL? {
        var url = URL(fileURLWithPath: file)
        url.deleteLastPathComponent() // Presets
        url.deleteLastPathComponent() // ReelForgeCore
        let dir = url.appendingPathComponent("Resources/presets")
        if FileManager.default.fileExists(atPath: dir.path) {
            return dir
        }
        return nil
    }
}
