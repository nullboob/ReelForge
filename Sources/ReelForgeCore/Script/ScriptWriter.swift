import Foundation

public enum ScriptWriter {
    public static func looksLikeFullScript(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let sentences = splitSentences(trimmed)
        if trimmed.count >= 180 && sentences.count >= 3 { return true }
        if trimmed.contains("\n") && sentences.count >= 2 { return true }
        return false
    }

    public static func parseUserScript(_ text: String) -> GeneratedScript {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count >= 3 {
            return GeneratedScript(
                hook: stripLabel(lines[0]),
                body: Array(lines.dropFirst().dropLast()).map(stripLabel),
                cta: stripLabel(lines[lines.count - 1]),
                source: .user
            )
        }

        let sentences = splitSentences(text)
        if sentences.count >= 3 {
            return GeneratedScript(
                hook: sentences[0],
                body: Array(sentences.dropFirst().dropLast()),
                cta: sentences[sentences.count - 1],
                source: .user
            )
        }

        return write(topic: text, presetID: "viral-hook", source: .user)
    }

    public static func parseModelOutput(_ text: String, fallbackTopic: String, presetID: String) -> GeneratedScript {
        var hook = ""
        var body: [String] = []
        var cta = ""

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("hook:") {
                hook = stripLabel(line)
            } else if lower.hasPrefix("cta:") || lower.hasPrefix("call to action:") {
                cta = stripLabel(line)
            } else if lower.hasPrefix("body:") || lower.hasPrefix("beat:") || numberedPrefix(line) != nil {
                body.append(stripLabel(line))
            } else if hook.isEmpty {
                hook = stripLabel(line)
            } else if cta.isEmpty && body.count >= 2 {
                cta = stripLabel(line)
            } else {
                body.append(stripLabel(line))
            }
        }

        if hook.isEmpty || body.isEmpty {
            return write(topic: fallbackTopic, presetID: presetID, source: .template)
        }
        if cta.isEmpty {
            cta = defaultCTA(for: fallbackTopic, presetID: presetID)
        }
        return GeneratedScript(hook: hook, body: body, cta: cta, source: .ollama)
    }

    public static func write(topic: String, presetID: String, source: ScriptSource = .template) -> GeneratedScript {
        let clean = collapseWhitespace(topic)
        let counted = extractCount(from: clean)
        let subject = counted?.subject ?? clean
        let n = counted?.count ?? defaultPointCount(presetID: presetID)

        switch presetID {
        case "product-demo":
            return productScript(topic: clean, subject: subject, count: max(3, n), source: source)
        case "tutorial-steps":
            return tutorialScript(topic: clean, subject: subject, count: max(3, n), source: source)
        case "youtube-short-news":
            return newsScript(topic: clean, subject: subject, count: max(3, n), source: source)
        case "luxury-brand":
            return luxuryScript(topic: clean, subject: subject, source: source)
        case "cinematic-story":
            return cinematicScript(topic: clean, subject: subject, source: source)
        case "travel-vlog":
            return travelScript(topic: clean, subject: subject, count: max(3, n), source: source)
        case "faceless-facts":
            return factsScript(topic: clean, subject: subject, count: max(3, n), source: source)
        default:
            return viralScript(topic: clean, subject: subject, count: max(3, n), source: source)
        }
    }

    public static func ollamaPrompt(topic: String, preset: Preset) -> String {
        """
        Write a spoken video script for a \(preset.durationSec)-second \(preset.aspect.rawValue) video.
        Style: \(preset.name) — \(preset.tagline)
        Topic: \(topic)

        Return plain text with these labeled lines and nothing else:
        HOOK: one punchy opening sentence
        BODY: one sentence
        BODY: one sentence
        BODY: one sentence
        CTA: one short closing ask

        Keep language spoken, concrete, and under 90 words total. No hashtags, no emoji.
        """
    }

    // MARK: - Styles

    private static func viralScript(topic: String, subject: String, count: Int, source: ScriptSource) -> GeneratedScript {
        let reasons = expandPoints(subject: subject, topic: topic, count: count, flavor: .viral)
        return GeneratedScript(
            hook: "Stop scrolling. \(capitalize(subject)) is about to make the usual advice look expensive.",
            body: reasons,
            cta: "Try it once this week, then tell me I am wrong. Follow for the next one.",
            source: source
        )
    }

    private static func factsScript(topic: String, subject: String, count: Int, source: ScriptSource) -> GeneratedScript {
        let facts = expandPoints(subject: subject, topic: topic, count: count, flavor: .facts)
        return GeneratedScript(
            hook: "Here are \(facts.count) things about \(lowercase(subject)) most people still get backward.",
            body: facts,
            cta: "Save this so you remember it later. More facts incoming.",
            source: source
        )
    }

    private static func productScript(topic: String, subject: String, count: Int, source: ScriptSource) -> GeneratedScript {
        let features = expandPoints(subject: subject, topic: topic, count: count, flavor: .product)
        return GeneratedScript(
            hook: "Meet the simpler way to handle \(lowercase(subject)).",
            body: features,
            cta: "If this solves the annoying part, it is already worth a look.",
            source: source
        )
    }

    private static func tutorialScript(topic: String, subject: String, count: Int, source: ScriptSource) -> GeneratedScript {
        let steps = expandPoints(subject: subject, topic: topic, count: count, flavor: .tutorial)
        return GeneratedScript(
            hook: "Do this in \(steps.count) calm steps and \(lowercase(subject)) stops feeling messy.",
            body: steps,
            cta: "Replay it once, then do the first step before you overthink it.",
            source: source
        )
    }

    private static func newsScript(topic: String, subject: String, count: Int, source: ScriptSource) -> GeneratedScript {
        let beats = expandPoints(subject: subject, topic: topic, count: count, flavor: .news)
        return GeneratedScript(
            hook: "Quick brief: \(capitalize(subject)).",
            body: beats,
            cta: "That is the cut. Follow for the next briefing.",
            source: source
        )
    }

    private static func luxuryScript(topic: String, subject: String, source: ScriptSource) -> GeneratedScript {
        return GeneratedScript(
            hook: "Quiet rooms. Slow light. \(capitalize(subject)).",
            body: [
                "Nothing here is rushed, because rush is the cheapest material you can use.",
                "The detail is the product: weight, finish, the pause before you speak.",
                "If it needs a shout, it is not finished."
            ],
            cta: "Look closer. Then decide if it belongs with you.",
            source: source
        )
    }

    private static func cinematicScript(topic: String, subject: String, source: ScriptSource) -> GeneratedScript {
        return GeneratedScript(
            hook: "It starts smaller than the story you tell later. \(capitalize(subject)).",
            body: [
                "First, the ordinary hour — the one nobody films.",
                "Then the turn: a choice that looks tiny until it is not.",
                "By the end you are not selling a tip. You are leaving a feeling that sticks."
            ],
            cta: "If this landed, sit with it. Then go make the next scene.",
            source: source
        )
    }

    private static func travelScript(topic: String, subject: String, count: Int, source: ScriptSource) -> GeneratedScript {
        let beats = expandPoints(subject: subject, topic: topic, count: count, flavor: .travel)
        return GeneratedScript(
            hook: "Pack lighter. \(capitalize(subject)) is a route, not a checklist.",
            body: beats,
            cta: "Go while the light is still interesting. Map the next one after.",
            source: source
        )
    }

    private enum Flavor {
        case viral, facts, product, tutorial, news, travel
    }

    private static func expandPoints(subject: String, topic: String, count: Int, flavor: Flavor) -> [String] {
        if let list = extractList(from: topic), list.count >= 2 {
            return list.prefix(max(count, list.count)).enumerated().map { index, item in
                decorate(item: item, index: index, flavor: flavor)
            }
        }

        let bank = pointBank(subject: subject, flavor: flavor)
        return (0..<count).map { index in
            decorate(item: bank[index % bank.count], index: index, flavor: flavor)
        }
    }

    private static func decorate(item: String, index: Int, flavor: Flavor) -> String {
        let text = capitalize(item)
        switch flavor {
        case .viral:
            return "Reason \(index + 1): \(lowercase(text))."
        case .facts:
            return "Fact \(index + 1): \(lowercase(text))."
        case .product:
            return "Feature \(index + 1): \(lowercase(text))."
        case .tutorial:
            return "Step \(index + 1): \(lowercase(text))."
        case .news:
            return "\(text)."
        case .travel:
            return "Then this: \(lowercase(text))."
        }
    }

    private static func pointBank(subject: String, flavor: Flavor) -> [String] {
        let s = lowercase(subject)
        switch flavor {
        case .viral:
            return [
                "\(s) costs less energy than the version you keep postponing",
                "tiny consistency beats a heroic session you skip",
                "your brain trusts a ritual it can finish before breakfast",
                "the compounding starts on day three, not day thirty",
                "you actually recover, which is the hidden advantage"
            ]
        case .facts:
            return [
                "most people overestimate intensity and underestimate frequency",
                "daylight plus movement changes attention more than another playlist",
                "a short outdoor loop is easier to repeat than a commute to a building",
                "low-friction habits survive busy weeks",
                "the body keeps score of what you repeat, not what you plan"
            ]
        case .product:
            return [
                "the first screen shows the outcome, not the settings",
                "setup takes a minute so you can judge it on real work",
                "the boring parts are automated so you stay on the decision",
                "it stays out of the way once it is configured",
                "export is one click, because the last mile is the product"
            ]
        case .tutorial:
            return [
                "write the outcome in one sentence so the rest has a target",
                "gather only the footage or notes you will actually use",
                "cut anything that does not move the story forward",
                "add captions and a bed only after the spine is right",
                "export, watch once on mute, then once with sound"
            ]
        case .news:
            return [
                "Here is what changed: \(s)",
                "Why it matters is the second-order effect, not the headline",
                "Watch the next move, not the noise around it"
            ]
        case .travel:
            return [
                "arrive before the postcard hour and let the streets wake up",
                "trade one landmark for a long walk with no route",
                "eat where the lunch line is local, not photographed",
                "leave room for the wrong turn — that is usually the frame"
            ]
        }
    }

    private static func defaultCTA(for topic: String, presetID: String) -> String {
        write(topic: topic, presetID: presetID).cta
    }

    private static func defaultPointCount(presetID: String) -> Int {
        switch presetID {
        case "luxury-brand", "cinematic-story": return 3
        case "tutorial-steps": return 4
        default: return 3
        }
    }

    // MARK: - Parsing helpers

    private static func extractCount(from text: String) -> (count: Int, subject: String)? {
        let pattern = #"^\s*(\d+)\s+(?:reasons?|ways?|tips?|steps?|things?|facts?|ideas?|features?)(?:\s+(?:why|that|to|for|your))?\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let countRange = Range(match.range(at: 1), in: text),
              let subjectRange = Range(match.range(at: 2), in: text),
              let count = Int(text[countRange])
        else { return nil }
        return (min(max(count, 2), 6), String(text[subjectRange]))
    }

    private static func extractList(from text: String) -> [String]? {
        let parts = text
            .components(separatedBy: CharacterSet(charactersIn: "•\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 3 { return parts.map(stripLabel) }
        return nil
    }

    private static func splitSentences(_ text: String) -> [String] {
        let cleaned = collapseWhitespace(text)
        guard !cleaned.isEmpty else { return [] }
        var sentences: [String] = []
        var current = ""
        for char in cleaned {
            current.append(char)
            if ".!?".contains(char) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if piece.count > 1 { sentences.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private static func numberedPrefix(_ line: String) -> Int? {
        let pattern = #"^\s*(?:body|beat|step|reason|fact)?\s*(\d+)[\).:\-]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let r = Range(match.range(at: 1), in: line)
        else { return nil }
        return Int(line[r])
    }

    private static func stripLabel(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = ["hook:", "body:", "cta:", "call to action:", "beat:", "step:", "reason:", "fact:", "feature:"]
        let lower = s.lowercased()
        for label in labels where lower.hasPrefix(label) {
            s = String(s.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        if let regex = try? NSRegularExpression(pattern: #"^\s*\d+[\).:\-]\s*"#),
           let match = regex.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let r = Range(match.range, in: s) {
            s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasSuffix(".") == false && s.hasSuffix("?") == false && s.hasSuffix("!") == false {
            s += "."
        }
        return capitalize(s)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    private static func capitalize(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func lowercase(_ text: String) -> String {
        guard let first = text.first else { return text }
        if text.count > 1, text.dropFirst().first?.isUppercase == true { return text }
        return first.lowercased() + text.dropFirst()
    }
}
