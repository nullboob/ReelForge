import Foundation

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var presetID: String
    public var topic: String
    public var scriptOverride: String?
    public var aspectOverride: AspectRatio?
    public var durationOverride: Int?
    public var useUnsplash: Bool
    public var usePexels: Bool
    public var useLocalAI: Bool
    public var burnCaptions: Bool
    public var exportSRT: Bool
    public var voiceIdentifier: String?
    public var voiceSpeed: Double
    public var beatPause: Double
    public var channelType: ChannelType
    public var target: VideoTarget
    public var language: ContentLanguage
    public var seriesName: String?
    public var script: GeneratedScript?
    public var storyboard: Storyboard?
    public var captions: [CaptionCue]
    public var assets: [AssetRef]
    public var attributions: [UnsplashAttribution]
    public var publishPack: PublishPack?
    public var ttsEngine: String?
    public var exportPath: String?
    public var warnings: [String]

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Reel",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        presetID: String = "viral-hook",
        topic: String = "",
        scriptOverride: String? = nil,
        aspectOverride: AspectRatio? = nil,
        durationOverride: Int? = nil,
        useUnsplash: Bool = true,
        usePexels: Bool = true,
        useLocalAI: Bool = true,
        burnCaptions: Bool = true,
        exportSRT: Bool = true,
        voiceIdentifier: String? = nil,
        voiceSpeed: Double = 1.0,
        beatPause: Double = 0.15,
        channelType: ChannelType = .facelessFacts,
        target: VideoTarget = .short,
        language: ContentLanguage = .english,
        seriesName: String? = nil,
        script: GeneratedScript? = nil,
        storyboard: Storyboard? = nil,
        captions: [CaptionCue] = [],
        assets: [AssetRef] = [],
        attributions: [UnsplashAttribution] = [],
        publishPack: PublishPack? = nil,
        ttsEngine: String? = nil,
        exportPath: String? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.presetID = presetID
        self.topic = topic
        self.scriptOverride = scriptOverride
        self.aspectOverride = aspectOverride
        self.durationOverride = durationOverride
        self.useUnsplash = useUnsplash
        self.usePexels = usePexels
        self.useLocalAI = useLocalAI
        self.burnCaptions = burnCaptions
        self.exportSRT = exportSRT
        self.voiceIdentifier = voiceIdentifier
        self.voiceSpeed = voiceSpeed
        self.beatPause = beatPause
        self.channelType = channelType
        self.target = target
        self.language = language
        self.seriesName = seriesName
        self.script = script
        self.storyboard = storyboard
        self.captions = captions
        self.assets = assets
        self.attributions = attributions
        self.publishPack = publishPack
        self.ttsEngine = ttsEngine
        self.exportPath = exportPath
        self.warnings = warnings
    }
}
