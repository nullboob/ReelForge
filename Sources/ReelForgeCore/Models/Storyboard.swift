import Foundation

public struct Storyboard: Codable, Equatable, Sendable {
    public var beats: [Beat]
    public var duration: Double
    public var presetID: String

    public init(beats: [Beat], duration: Double, presetID: String) {
        self.beats = beats
        self.duration = duration
        self.presetID = presetID
    }
}
