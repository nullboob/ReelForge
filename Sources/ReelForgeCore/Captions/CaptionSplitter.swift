import Foundation

public enum CaptionSplitter {
    public static func cues(
        from script: GeneratedScript,
        duration: Double,
        maxWordsPerCard: Int,
        storyboard: Storyboard? = nil
    ) -> [CaptionCue] {
        if let storyboard, !storyboard.beats.isEmpty {
            return cuesAlignedToBeats(script: script, storyboard: storyboard, maxWordsPerCard: maxWordsPerCard)
        }
        return align(text: script.fullText, duration: duration, maxWordsPerCard: maxWordsPerCard)
    }

    public static func align(
        text: String,
        duration: Double,
        maxWordsPerCard: Int
    ) -> [CaptionCue] {
        let words = tokenize(text)
        guard !words.isEmpty, duration > 0 else { return [] }
        let cards = pack(words: words, maxWords: max(1, maxWordsPerCard))
        return timeCards(cards, duration: duration)
    }

    public static func cuesAlignedToBeats(
        script: GeneratedScript,
        storyboard: Storyboard,
        maxWordsPerCard: Int
    ) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        for beat in storyboard.beats {
            let text = beat.text.isEmpty ? script.fullText : beat.text
            let slice = align(text: text, duration: beat.duration, maxWordsPerCard: maxWordsPerCard)
            for var cue in slice {
                cue.start += beat.start
                cue.words = cue.words.map {
                    WordTiming(word: $0.word, start: $0.start + beat.start, duration: $0.duration)
                }
                cues.append(cue)
            }
        }
        return relabel(cues)
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func pack(words: [String], maxWords: Int) -> [[String]] {
        var cards: [[String]] = []
        var current: [String] = []
        for word in words {
            current.append(word)
            let punct = word.last.map { ".!?".contains($0) } ?? false
            if current.count >= maxWords || punct {
                cards.append(current)
                current = []
            }
        }
        if !current.isEmpty { cards.append(current) }
        return cards
    }

    private static func timeCards(_ cards: [[String]], duration: Double) -> [CaptionCue] {
        let weights = cards.map { Double(max(1, $0.joined().count)) }
        let sum = weights.reduce(0, +)
        var cursor = 0.0
        var cues: [CaptionCue] = []
        for (index, card) in cards.enumerated() {
            var d = duration * (weights[index] / max(sum, 1))
            d = max(0.28, d)
            if index == cards.count - 1 {
                d = max(0.28, duration - cursor)
            }
            let words = wordTimings(card, start: cursor, duration: d)
            cues.append(
                CaptionCue(
                    id: "cue-\(index)",
                    text: card.joined(separator: " "),
                    start: cursor,
                    duration: d,
                    words: words,
                    highlightWordIndex: card.count > 2 ? min(card.count - 1, 1) : 0
                )
            )
            cursor += d
        }
        return cues
    }

    private static func wordTimings(_ words: [String], start: Double, duration: Double) -> [WordTiming] {
        let weights = words.map { Double(max(1, $0.count)) }
        let sum = weights.reduce(0, +)
        var cursor = start
        return words.enumerated().map { index, word in
            let d = duration * (weights[index] / max(sum, 1))
            let timing = WordTiming(word: word, start: cursor, duration: d)
            cursor += d
            return timing
        }
    }

    private static func relabel(_ cues: [CaptionCue]) -> [CaptionCue] {
        cues.enumerated().map { index, cue in
            var next = cue
            next.id = "cue-\(index)"
            return next
        }
    }
}
