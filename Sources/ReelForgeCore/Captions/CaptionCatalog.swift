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
    public var karaoke: String
    public var position: String
    public var maxWords: Int
    public var maxSeconds: Double
    public var renderer: String
    public var allCaps: Bool
    public var outline: Int
    public var shadow: Int
    public var gradient: [String]
    public var angle: Double
    public var primitive: String
    public var role: String

    public init(
        id: String,
        name: String,
        font: String,
        fontFile: String,
        size: Double,
        fill: String,
        stroke: String,
        highlight: String,
        plate: String,
        plateFill: String? = nil,
        animation: String,
        karaoke: String = "snap",
        position: String,
        maxWords: Int,
        maxSeconds: Double = 2,
        renderer: String,
        allCaps: Bool,
        outline: Int,
        shadow: Int,
        gradient: [String],
        angle: Double = 0,
        primitive: String = "karaoke-color",
        role: String = "body"
    ) {
        self.id = id
        self.name = name
        self.font = font
        self.fontFile = fontFile
        self.size = size
        self.fill = fill
        self.stroke = stroke
        self.highlight = highlight
        self.plate = plate
        self.plateFill = plateFill
        self.animation = animation
        self.karaoke = karaoke
        self.position = position
        self.maxWords = maxWords
        self.maxSeconds = maxSeconds
        self.renderer = renderer
        self.allCaps = allCaps
        self.outline = outline
        self.shadow = shadow
        self.gradient = gradient
        self.angle = angle
        self.primitive = primitive
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        font = try c.decode(String.self, forKey: .font)
        fontFile = try c.decode(String.self, forKey: .fontFile)
        size = try c.decode(Double.self, forKey: .size)
        fill = try c.decode(String.self, forKey: .fill)
        stroke = try c.decode(String.self, forKey: .stroke)
        highlight = try c.decode(String.self, forKey: .highlight)
        plate = try c.decode(String.self, forKey: .plate)
        plateFill = try c.decodeIfPresent(String.self, forKey: .plateFill)
        animation = try c.decode(String.self, forKey: .animation)
        karaoke = try c.decodeIfPresent(String.self, forKey: .karaoke) ?? "snap"
        position = try c.decode(String.self, forKey: .position)
        maxWords = try c.decode(Int.self, forKey: .maxWords)
        maxSeconds = try c.decodeIfPresent(Double.self, forKey: .maxSeconds) ?? 2
        renderer = try c.decode(String.self, forKey: .renderer)
        allCaps = try c.decode(Bool.self, forKey: .allCaps)
        outline = try c.decode(Int.self, forKey: .outline)
        shadow = try c.decode(Int.self, forKey: .shadow)
        gradient = try c.decodeIfPresent([String].self, forKey: .gradient) ?? []
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0
        primitive = try c.decodeIfPresent(String.self, forKey: .primitive) ?? "karaoke-color"
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "body"
    }

    public func asCaptionStyle() -> CaptionStyle {
        let pos: CaptionPosition = position == "bottom" ? .bottom : .center
        let anim: CaptionAnimation
        switch animation {
        case "pop-scale", "bounce": anim = .pop
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
    public var aliases: [String: String]
    public var styles: [CaptionLook]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        defaultStyleID = try c.decode(String.self, forKey: .defaultStyleID)
        presetDefaults = try c.decodeIfPresent([String: String].self, forKey: .presetDefaults) ?? [:]
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        styles = try c.decode([CaptionLook].self, forKey: .styles)
    }
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
        "tiktok-classic-outline", "hormozi-yellow-pop", "karaoke-yellow-sweep", "word-pop-sync",
        "single-word-center", "bounce-fitness", "typewriter-story", "quiet-aesthetic-min",
        "color-switch-strobe", "commentary-telegraph", "kinetic-hook-slide", "neon-glow-pulse",
        "outline-double-stroke", "faceless-stack-highlight", "podcast-split-karaoke", "cinematic-gold-fade",
        "boxed-pill-yellow", "beast-3d-pop", "listicle-number-chip", "boxed-kinetic-bar",
        "cta-urgent-red", "gradient-rainbow-word", "gradient-sunset-fill", "gradient-chrome-metallic",
        "gradient-neon-cyan-magenta", "gradient-gold-metallic", "gradient-fire", "gradient-ice",
        "gradient-candy", "gradient-duotone-yellow-pink"
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

    public static func resolve(id: String?) -> String {
        let file = try? loadFile()
        var current = id ?? file?.defaultStyleID ?? "tiktok-classic-outline"
        var seen = Set<String>()
        let aliases = file?.aliases ?? [:]
        while let next = aliases[current], !seen.contains(current) {
            seen.insert(current)
            current = next
        }
        return current
    }

    public static func look(id: String?) -> CaptionLook {
        let file = try? loadFile()
        let styles = file?.styles ?? []
        let resolved = resolve(id: id)
        if let match = styles.first(where: { $0.id == resolved }) {
            return match
        }
        let fallback = file?.defaultStyleID ?? "tiktok-classic-outline"
        return styles.first(where: { $0.id == fallback }) ?? styles.first ?? CaptionLook(
            id: "tiktok-classic-outline",
            name: "TikTok Classic Outline",
            font: "Montserrat ExtraBold",
            fontFile: "Montserrat-ExtraBold.ttf",
            size: 72,
            fill: "#FFFFFF",
            stroke: "#111111",
            highlight: "#FFFFFF",
            plate: "none",
            animation: "karaoke-word",
            position: "center",
            maxWords: 3,
            renderer: "ass",
            allCaps: false,
            outline: 6,
            shadow: 2,
            gradient: []
        )
    }

    public static func defaultID(forPreset presetID: String) -> String {
        let file = try? loadFile()
        return resolve(id: file?.presetDefaults[presetID] ?? file?.defaultStyleID ?? "tiktok-classic-outline")
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
