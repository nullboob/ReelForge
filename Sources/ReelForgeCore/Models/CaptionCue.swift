import Foundation

public struct WordTiming: Codable, Equatable, Sendable {
    public var word: String
    public var start: Double
    public var duration: Double

    public init(word: String, start: Double, duration: Double) {
        self.word = word
        self.start = start
        self.duration = duration
    }
}

public struct CaptionCue: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var start: Double
    public var duration: Double
    public var words: [WordTiming]
    public var highlightWordIndex: Int?

    public init(
        id: String,
        text: String,
        start: Double,
        duration: Double,
        words: [WordTiming],
        highlightWordIndex: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
        self.words = words
        self.highlightWordIndex = highlightWordIndex
    }

    public var end: Double { start + duration }
}
