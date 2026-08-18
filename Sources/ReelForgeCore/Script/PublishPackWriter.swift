import Foundation

public enum PublishPackWriter {
    public static func write(
        topic: String,
        script: GeneratedScript,
        storyboard: Storyboard,
        preset: Preset,
        channel: ChannelKit,
        series: String?,
        target: VideoTarget
    ) -> PublishPack {
        let title = makeTitle(topic: topic, script: script, series: series, channel: channel)
        let chapters = chapters(from: storyboard)
        let description = makeDescription(
            script: script,
            chapters: chapters,
            channel: channel,
            series: series,
            target: target
        )
        let tags = makeTags(topic: topic, preset: preset, channel: channel, series: series)
        let hashtags = Array(tags.prefix(4)).map { "#\($0.replacingOccurrences(of: " ", with: ""))" }
        let slug = slugify(title)
        return PublishPack(
            title: title,
            description: description,
            tags: tags,
            hashtags: hashtags,
            chapters: chapters,
            suggestedFilename: "\(slug).mp4",
            source: .template
        )
    }

    public static func parseModelOutput(
        _ text: String,
        fallback: PublishPack
    ) -> PublishPack {
        var title = fallback.title
        var description = fallback.description
        var tags = fallback.tags
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("title:") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("description:") {
                description = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("tags:") {
                tags = String(line.dropFirst(5))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        var pack = fallback
        pack.title = clip(title, 70)
        if !description.isEmpty { pack.description = description }
        if !tags.isEmpty { pack.tags = tags }
        pack.source = .ollama
        return pack
    }

    public static func ollamaPrompt(topic: String, script: GeneratedScript, channel: ChannelKit) -> String {
        """
        Write YouTube packaging for a faceless video.
        Channel: \(channel.name.isEmpty ? "independent creator" : channel.name)
        Topic: \(topic)
        Hook: \(script.hook)

        Return labeled lines only:
        TITLE: under 70 characters, curiosity plus payoff, no all-caps
        DESCRIPTION: two hook sentences, then a subscribe CTA
        TAGS: 8 comma-separated lowercase tags
        """
    }

    public static func chapters(from storyboard: Storyboard) -> [ChapterMark] {
        storyboard.beats.map { beat in
            let raw = beat.text.split(separator: " ").prefix(8).joined(separator: " ")
            return ChapterMark(id: beat.id, start: beat.start, title: raw)
        }
    }

    private static func makeTitle(topic: String, script: GeneratedScript, series: String?, channel: ChannelKit) -> String {
        var base = script.hook
        if base.count > 68 {
            base = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let series, !series.isEmpty {
            let mixed = "\(series): \(base)"
            if mixed.count <= 70 { base = mixed }
        }
        _ = channel
        return clip(base.replacingOccurrences(of: "\"", with: ""), 70)
    }

    private static func makeDescription(
        script: GeneratedScript,
        chapters: [ChapterMark],
        channel: ChannelKit,
        series: String?,
        target: VideoTarget
    ) -> String {
        let hook = script.hook
        let second = script.body.first ?? script.cta
        var lines = [hook, second, ""]
        if let series, !series.isEmpty {
            lines.append("Series: \(series)")
        }
        if !channel.name.isEmpty {
            lines.append("\(channel.name) — new videos for people building in public.")
        }
        lines.append("")
        lines.append("Chapters")
        for chapter in chapters.prefix(12) {
            lines.append("\(chapter.timestamp) \(chapter.title)")
        }
        lines.append("")
        lines.append(script.cta)
        if target == .short {
            lines.append("More shorts on the channel. Subscribe if this saved you a search.")
        } else {
            lines.append("If this helped, subscribe and drop the next topic in the comments.")
        }
        return lines.joined(separator: "\n")
    }

    private static func makeTags(topic: String, preset: Preset, channel: ChannelKit, series: String?) -> [String] {
        var tags = [
            "youtube shorts",
            "faceless youtube",
            preset.name.lowercased(),
            "how to",
            "explained"
        ]
        let words = topic.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }.filter { $0.count > 3 }
        tags.append(contentsOf: words.prefix(4))
        if let series, !series.isEmpty { tags.append(series.lowercased()) }
        if !channel.name.isEmpty { tags.append(channel.name.lowercased()) }
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }.prefix(12).map { $0 }
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func slugify(_ text: String) -> String {
        let parts = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
        return parts.isEmpty ? "reelforge-video" : parts.joined(separator: "-")
    }
}
