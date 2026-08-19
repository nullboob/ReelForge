import Foundation

/// Per-channel Pexels `video.id` blacklist so the same clip is not reused across ~20 videos.
enum ClipBlacklist {
    private static let reuseLimit = 20

    private static func url(for channel: String) -> URL {
        let slug = channel
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let name = slug.isEmpty ? "default" : slug
        return ProjectStore.root.appendingPathComponent("pexels-blacklist-\(name).json")
    }

    static func load(channel: String) -> Set<Int> {
        guard let data = try? Data(contentsOf: url(for: channel)),
              let ids = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return Set(ids)
    }

    static func remember(_ id: Int, channel: String) {
        guard id > 0 else { return }
        var ids = load(channel: channel)
        ids.insert(id)
        let trimmed = Array(ids.sorted().suffix(reuseLimit * 8))
        try? FileManager.default.createDirectory(at: ProjectStore.root, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: url(for: channel), options: .atomic)
        }
    }
}
