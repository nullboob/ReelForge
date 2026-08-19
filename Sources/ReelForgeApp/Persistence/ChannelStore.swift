import Foundation

enum ChannelStore {
    static var url: URL {
        ProjectStore.root.appendingPathComponent("channel.json")
    }

    static func load() -> ChannelKit {
        guard let data = try? Data(contentsOf: url),
              let kit = try? JSONDecoder().decode(ChannelKit.self, from: data)
        else { return ChannelKit() }
        return kit
    }

    static func save(_ kit: ChannelKit) {
        try? FileManager.default.createDirectory(at: ProjectStore.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(kit) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func logoURL(for kit: ChannelKit) -> URL? {
        guard let relative = kit.logoRelativePath else { return nil }
        let url = ProjectStore.root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func saveLogo(_ source: URL) -> String? {
        let dest = ProjectStore.root.appendingPathComponent("logo.png")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return "logo.png"
        } catch {
            return nil
        }
    }
}
