import Foundation

public enum AssetKind: String, Codable, Sendable {
    case video
    case image
    case generatedCard
    case voiceover
    case music
}

public struct UnsplashAttribution: Codable, Equatable, Sendable {
    public var photographer: String
    public var photographerURL: String
    public var photoURL: String
    public var beatID: String

    public init(photographer: String, photographerURL: String, photoURL: String, beatID: String) {
        self.photographer = photographer
        self.photographerURL = photographerURL
        self.photoURL = photoURL
        self.beatID = beatID
    }
}

public struct AssetRef: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: AssetKind
    public var relativePath: String
    public var beatID: String?
    public var attribution: UnsplashAttribution?

    public init(
        id: String,
        kind: AssetKind,
        relativePath: String,
        beatID: String? = nil,
        attribution: UnsplashAttribution? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.beatID = beatID
        self.attribution = attribution
    }
}
