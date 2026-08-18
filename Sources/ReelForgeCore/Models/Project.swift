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
    public var useLocalAI: Bool
    public var voiceIdentifier: String?
    public var script: GeneratedScript?
    public var storyboard: Storyboard?
    public var captions: [CaptionCue]
    public var assets: [AssetRef]
    public var attributions: [UnsplashAttribution]
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
        useLocalAI: Bool = true,
        voiceIdentifier: String? = nil,
        script: GeneratedScript? = nil,
        storyboard: Storyboard? = nil,
        captions: [CaptionCue] = [],
        assets: [AssetRef] = [],
        attributions: [UnsplashAttribution] = [],
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
        self.useLocalAI = useLocalAI
        self.voiceIdentifier = voiceIdentifier
        self.script = script
        self.storyboard = storyboard
        self.captions = captions
        self.assets = assets
        self.attributions = attributions
        self.exportPath = exportPath
        self.warnings = warnings
    }
}
