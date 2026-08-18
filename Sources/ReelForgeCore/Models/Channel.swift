import Foundation

public enum ChannelType: String, Codable, CaseIterable, Sendable {
    case facelessFacts
    case listicle
    case explainer
    case storytime
    case product
    case commentary
    case news

    public var displayName: String {
        switch self {
        case .facelessFacts: return "Faceless facts"
        case .listicle: return "Listicle"
        case .explainer: return "Explainer"
        case .storytime: return "Storytime"
        case .product: return "Product"
        case .commentary: return "Commentary"
        case .news: return "News"
        }
    }

    public var suggestedPresetID: String {
        switch self {
        case .facelessFacts: return "faceless-facts"
        case .listicle: return "listicle"
        case .explainer: return "explainer"
        case .storytime: return "storytime"
        case .product: return "product-demo"
        case .commentary: return "motivational"
        case .news: return "news-roundup"
        }
    }
}

public enum VideoTarget: String, Codable, CaseIterable, Sendable {
    case short
    case longForm

    public var displayName: String {
        switch self {
        case .short: return "YouTube Short"
        case .longForm: return "Long-form"
        }
    }

    public var defaultAspect: AspectRatio {
        switch self {
        case .short: return .vertical
        case .longForm: return .landscape
        }
    }

    public var durationChoices: [Int] {
        switch self {
        case .short: return [15, 30, 45, 60]
        case .longForm: return [180, 300, 480]
        }
    }

    public var defaultDuration: Int {
        switch self {
        case .short: return 30
        case .longForm: return 180
        }
    }
}

public enum ContentLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"

    public var displayName: String { "English" }
}

public struct ChannelKit: Codable, Equatable, Sendable {
    public var name: String
    public var primaryHex: String
    public var accentHex: String
    public var logoRelativePath: String?
    public var introSeconds: Double
    public var outroEnabled: Bool
    public var defaultVoice: String?
    public var defaultPresetID: String
    public var defaultAspect: AspectRatio?

    public init(
        name: String = "",
        primaryHex: String = "#FF4D6D",
        accentHex: String = "#E8C39A",
        logoRelativePath: String? = nil,
        introSeconds: Double = 0,
        outroEnabled: Bool = true,
        defaultVoice: String? = nil,
        defaultPresetID: String = "viral-hook",
        defaultAspect: AspectRatio? = nil
    ) {
        self.name = name
        self.primaryHex = primaryHex
        self.accentHex = accentHex
        self.logoRelativePath = logoRelativePath
        self.introSeconds = min(3, max(0, introSeconds))
        self.outroEnabled = outroEnabled
        self.defaultVoice = defaultVoice
        self.defaultPresetID = defaultPresetID
        self.defaultAspect = defaultAspect
    }
}

public struct ChapterMark: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: Double
    public var title: String

    public init(id: String, start: Double, title: String) {
        self.id = id
        self.start = start
        self.title = title
    }

    public var timestamp: String {
        let total = max(0, Int(start.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

public struct PublishPack: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var tags: [String]
    public var hashtags: [String]
    public var chapters: [ChapterMark]
    public var thumbnailPath: String?
    public var srtPath: String?
    public var suggestedFilename: String
    public var source: ScriptSource

    public init(
        title: String,
        description: String,
        tags: [String],
        hashtags: [String],
        chapters: [ChapterMark],
        thumbnailPath: String? = nil,
        srtPath: String? = nil,
        suggestedFilename: String,
        source: ScriptSource
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.hashtags = hashtags
        self.chapters = chapters
        self.thumbnailPath = thumbnailPath
        self.srtPath = srtPath
        self.suggestedFilename = suggestedFilename
        self.source = source
    }
}
