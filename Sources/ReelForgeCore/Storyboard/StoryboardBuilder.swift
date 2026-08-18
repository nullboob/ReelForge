import Foundation

public enum StoryboardBuilder {
    public static func build(
        script: GeneratedScript,
        preset: Preset,
        duration: Double
    ) -> Storyboard {
        let target = max(8, duration)
        var raw = rawUnits(from: script, numbered: preset.titleCard.numbered)
        raw = fitCount(raw, pace: preset.pace, duration: target)

        let weights = raw.map { Double(max(8, $0.text.count)) }
        let weightSum = weights.reduce(0, +)
        let minC = preset.pace.cutMinSec
        let maxC = preset.pace.cutMaxSec

        var durations = weights.map { target * ($0 / weightSum) }
        durations = durations.map { min(max($0, minC), maxC) }

        let clampedSum = durations.reduce(0, +)
        if clampedSum > 0 {
            let scale = target / clampedSum
            durations = durations.map { $0 * scale }
        }
        if let last = durations.indices.last {
            let drift = target - durations.reduce(0, +)
            durations[last] = max(0.4, durations[last] + drift)
        }

        var cursor = 0.0
        var beats: [Beat] = []
        let queries = preset.footage.unsplashQueries.isEmpty ? ["cinematic texture"] : preset.footage.unsplashQueries

        for (index, unit) in raw.enumerated() {
            let duration = durations[index]
            let query = queryForBeat(text: unit.text, hints: queries, index: index)
            let beat = Beat(
                id: "beat-\(index)",
                index: index,
                role: unit.role,
                text: unit.text,
                start: cursor,
                duration: duration,
                unsplashQuery: query,
                stepNumber: unit.step
            )
            beats.append(beat)
            cursor += duration
        }

        return Storyboard(beats: beats, duration: cursor, presetID: preset.id)
    }

    public static func rescale(_ storyboard: Storyboard, to duration: Double) -> Storyboard {
        let current = max(0.01, storyboard.duration)
        let scale = duration / current
        var cursor = 0.0
        let beats = storyboard.beats.map { beat -> Beat in
            var next = beat
            next.start = cursor
            next.duration = beat.duration * scale
            cursor += next.duration
            return next
        }
        return Storyboard(beats: beats, duration: cursor, presetID: storyboard.presetID)
    }

    private struct Unit {
        var role: BeatRole
        var text: String
        var step: Int?
    }

    private static func rawUnits(from script: GeneratedScript, numbered: Bool) -> [Unit] {
        var units: [Unit] = []
        if !script.hook.isEmpty {
            units.append(Unit(role: .hook, text: script.hook, step: numbered ? 0 : nil))
        }
        for (i, line) in script.body.enumerated() where !line.isEmpty {
            units.append(Unit(role: .body(i), text: line, step: numbered ? i + 1 : nil))
        }
        if !script.cta.isEmpty {
            units.append(Unit(role: .cta, text: script.cta, step: nil))
        }
        if units.isEmpty {
            units.append(Unit(role: .hook, text: "Stay with this for a second.", step: numbered ? 1 : nil))
        }
        return units
    }

    private static func fitCount(_ units: [Unit], pace: Pace, duration: Double) -> [Unit] {
        var result = units
        let minC = pace.cutMinSec
        let maxC = pace.cutMaxSec
        let avg = max(0.6, pace.averageCut)
        var targetCount = Int((duration / avg).rounded())
        targetCount = min(max(targetCount, 3), 16)

        while result.count * minC > duration + 0.01 && result.count > 3 {
            result = mergeShortestBody(result)
        }

        var guardCounter = 0
        while result.count < targetCount && result.count * maxC < duration && guardCounter < 12 {
            guard let idx = longestSplittableIndex(result) else { break }
            result = split(result, at: idx)
            guardCounter += 1
        }
        return result
    }

    private static func mergeShortestBody(_ units: [Unit]) -> [Unit] {
        guard units.count > 1 else { return units }
        var best = -1
        var bestLen = Int.max
        for i in 0..<(units.count - 1) {
            if case .hook = units[i].role { continue }
            let combined = units[i].text.count + units[i + 1].text.count
            if combined < bestLen {
                bestLen = combined
                best = i
            }
        }
        if best < 0 { best = max(0, units.count - 2) }
        var next = units
        next[best].text = next[best].text.trimmingCharacters(in: .whitespaces) + " " + next[best + 1].text
        next.remove(at: best + 1)
        return next
    }

    private static func longestSplittableIndex(_ units: [Unit]) -> Int? {
        var best: Int?
        var bestCount = 0
        for (i, unit) in units.enumerated() {
            let parts = splitText(unit.text)
            if parts.count >= 2, unit.text.count > bestCount {
                best = i
                bestCount = unit.text.count
            }
        }
        return best
    }

    private static func split(_ units: [Unit], at index: Int) -> [Unit] {
        let parts = splitText(units[index].text)
        guard parts.count >= 2 else { return units }
        let mid = parts.count / 2
        let left = parts[..<mid].joined(separator: " ")
        let right = parts[mid...].joined(separator: " ")
        var next = units
        next[index].text = left
        let inserted = Unit(role: units[index].role, text: right, step: units[index].step)
        next.insert(inserted, at: index + 1)
        return next
    }

    private static func splitText(_ text: String) -> [String] {
        let byComma = text.split(separator: ",", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if byComma.count >= 2 { return byComma }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count >= 8 {
            let mid = words.count / 2
            return [words[..<mid].joined(separator: " "), words[mid...].joined(separator: " ")]
        }
        return [text]
    }

    private static func queryForBeat(text: String, hints: [String], index: Int) -> String {
        let hint = hints[index % hints.count]
        let keyword = interestingKeyword(in: text)
        if let keyword, keyword.count > 3 {
            return "\(hint) \(keyword)"
        }
        return hint
    }

    private static func interestingKeyword(in text: String) -> String? {
        let stop: Set<String> = [
            "this", "that", "with", "from", "your", "about", "have", "just", "then",
            "than", "they", "them", "what", "when", "stop", "here", "most", "people",
            "reason", "step", "fact", "feature", "meet", "quick", "brief"
        ]
        return text
            .split(whereSeparator: { !$0.isLetter })
            .map { $0.lowercased() }
            .first { $0.count > 4 && !stop.contains($0) }
    }
}
