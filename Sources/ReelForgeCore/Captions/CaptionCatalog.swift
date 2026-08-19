import Foundation

public struct CaptionLook: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var font: String
    public var fontFile: String
    public var size: Double
    public var fill: String
    public var stroke: String
    public var highlight: String
    public var plate: String
    public var plateFill: String?
    public var animation: String
    public var position: String
    public var maxWords: Int
    public var renderer: String
    public var allCaps: Bool
    public var outline: Int
    public var shadow: Int
    public var gradient: [String]

    public func asCaptionStyle() -> CaptionStyle {
        let pos: CaptionPosition = position == "bottom" ? .bottom : .center
        let anim: CaptionAnimation
        switch animation {
        case "pop-scale": anim = .pop
        case "typewriter": anim = .wordByWord
        default: anim = .karaoke
        }
        return CaptionStyle(
            font: font,
            size: size,
            weight: "heavy",
            fill: fill,
            stroke: stroke,
            highlight: highlight,
            position: pos,
            maxWordsPerCard: maxWords,
            animation: anim
        )
    }
}

public struct CaptionCatalogFile: Codable, Equatable, Sendable {
    public var version: Int
    public var defaultStyleID: String
    public var presetDefaults: [String: String]
    public var styles: [CaptionLook]
}

public enum CaptionCatalogError: Error, LocalizedError {
    case missing
    case decodeFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .missing: return "Caption style catalog was not found."
        case .decodeFailed(let error): return "Caption catalog failed to decode: \(error.localizedDescription)"
        }
    }
}

public enum CaptionCatalog {
    public static let requiredIDs = [
        "dynamic-minimal", "hormozi-classic", "pill-black", "pill-yellow", "pill-hot", "pill-brand",
        "capcut-classic", "most-readable", "fancy-soft", "checksub-rose", "glow-clean", "boxed-outline",
        "typewriter", "color-switch", "quiet-aesthetic", "bebas-sports", "archivo-hype", "tiktok-native",
        "sunset-fill", "candy-pop", "neon-cyber", "gold-metallic", "fire-sweep", "ice-chrome",
        "rainbow-word", "duotone-sun", "chrome-silver", "ocean-teal", "grape-aurora", "lime-punch"
    ]

    public static func loadFile() throws -> CaptionCatalogFile {
        guard let url = catalogURL() else { throw CaptionCatalogError.missing }
        do {
            return try JSONDecoder().decode(CaptionCatalogFile.self, from: Data(contentsOf: url))
        } catch {
            throw CaptionCatalogError.decodeFailed(error)
        }
    }

    public static func load() throws -> [CaptionLook] {
        try loadFile().styles
    }

    public static func look(id: String?) -> CaptionLook {
        let file = (try? loadFile())
        let styles = file?.styles ?? []
        if let id, let match = styles.first(where: { $0.id == id }) {
            return match
        }
        let fallback = file?.defaultStyleID ?? "dynamic-minimal"
        return styles.first(where: { $0.id == fallback }) ?? styles.first ?? CaptionLook(
            id: "dynamic-minimal",
            name: "Dynamic Minimal",
            font: "Montserrat ExtraBold",
            fontFile: "Montserrat-ExtraBold.ttf",
            size: 72,
            fill: "#FFFFFF",
            stroke: "#111111",
            highlight: "#FFFFFF",
            plate: "none",
            plateFill: nil,
            animation: "karaoke-word",
            position: "center",
            maxWords: 5,
            renderer: "ass",
            allCaps: false,
            outline: 6,
            shadow: 2,
            gradient: []
        )
    }

    public static func defaultID(forPreset presetID: String) -> String {
        let file = try? loadFile()
        return file?.presetDefaults[presetID] ?? file?.defaultStyleID ?? "dynamic-minimal"
    }

    public static func catalogURL() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "caption-styles") {
            return url
        }
        if let url = Bundle.module.resourceURL?.appendingPathComponent("caption-styles/catalog.json"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "caption-styles") {
            return url
        }
        return sourceTreeCatalog()
    }

    public static func fontsDirectory() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.resourceURL?.appendingPathComponent("fonts"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        #endif
        if let url = Bundle.main.resourceURL?.appendingPathComponent("fonts"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let catalog = sourceTreeCatalog() {
            return catalog.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fonts")
        }
        return nil
    }

    public static func fontURL(file: String) -> URL? {
        guard let dir = fontsDirectory() else { return nil }
        let url = dir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static func sourceTreeCatalog(file: String = #file) -> URL? {
        var url = URL(fileURLWithPath: file)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        let catalog = url.appendingPathComponent("Resources/caption-styles/catalog.json")
        if FileManager.default.fileExists(atPath: catalog.path) {
            return catalog
        }
        return nil
    }
}
