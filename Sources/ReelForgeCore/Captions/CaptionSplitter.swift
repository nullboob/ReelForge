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
        let cards = pack(words: words, maxWords: max(1, min(maxWordsPerCard, 12)))
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
            let slice: [CaptionCue]
            if case .hook = beat.role {
                slice = [hookCard(text: text, duration: beat.duration, maxWords: maxWordsPerCard)]
            } else {
                slice = align(text: text, duration: beat.duration, maxWordsPerCard: maxWordsPerCard)
            }
            for var cue in slice {
                cue.start += beat.start
                cue.words = cue.words.map {
                    WordTiming(word: $0.word, start: $0.start + beat.start, duration: $0.duration)
                }
                cues.append(cue)
            }
        }
        return exclusive(relabel(cues))
    }

    public static func hookCard(text: String, duration: Double, maxWords: Int) -> CaptionCue {
        let words = tokenize(text)
        var card: [String] = []
        let limit = max(1, min(maxWords, 6))
        for word in words {
            card.append(word)
            let punct = word.last.map { ".!?".contains($0) } ?? false
            if punct && card.count >= 2 { break }
            if card.count >= limit { break }
        }
        if card.isEmpty { card = ["Watch this"] }
        return timeCards([card], duration: max(0.4, duration))[0]
    }

    public static func exclusive(_ cues: [CaptionCue]) -> [CaptionCue] {
        guard !cues.isEmpty else { return [] }
        var ordered = cues.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.duration > rhs.duration }
            return lhs.start < rhs.start
        }
        var out: [CaptionCue] = []
        for index in ordered.indices {
            var cue = ordered[index]
            var end = cue.start + max(0.04, cue.duration)
            if index + 1 < ordered.count {
                if ordered[index + 1].start <= cue.start {
                    ordered[index + 1].start = cue.start + 0.04
                }
                end = min(end, ordered[index + 1].start)
            }
            let duration = max(0.04, end - cue.start)
            cue.duration = duration
            let tokens = cue.words.map(\.word).filter { !$0.isEmpty }
            cue.words = wordTimings(tokens.isEmpty ? cue.text.split(separator: " ").map(String.init) : tokens, start: cue.start, duration: duration)
            out.append(cue)
        }
        return out
    }

    public static func overlappingPairs(_ cues: [CaptionCue], epsilon: Double = 1e-4) -> [(String, String)] {
        var hits: [(String, String)] = []
        for (index, left) in cues.enumerated() {
            for right in cues.dropFirst(index + 1) {
                if left.start < right.end - epsilon && right.start < left.end - epsilon {
                    hits.append((left.id, right.id))
                }
            }
        }
        return hits
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
            let punct = word.last.map { ".!?,;:".contains($0) } ?? false
            if current.count >= maxWords || (punct && current.count >= 2) {
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
        let raw = weights.map { duration * ($0 / max(sum, 1)) }
        var cursor = 0.0
        var cues: [CaptionCue] = []
        for (index, card) in cards.enumerated() {
            let remaining = cards.count - index
            let leftover = duration - cursor
            let d: Double
            if remaining == 1 {
                d = leftover
            } else {
                let floor = 0.04 * Double(remaining - 1)
                d = min(raw[index], max(0.04, leftover - floor))
            }
            let held = max(0.04, d)
            let words = wordTimings(card, start: cursor, duration: held)
            cues.append(
                CaptionCue(
                    id: "cue-\(index)",
                    text: card.joined(separator: " "),
                    start: cursor,
                    duration: held,
                    words: words,
                    highlightWordIndex: card.count > 2 ? min(card.count - 1, 1) : 0
                )
            )
            cursor += held
        }
        return exclusive(cues)
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
