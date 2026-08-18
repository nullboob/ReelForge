import Foundation

enum ProjectStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ReelForge", isDirectory: true)
    }

    static func directory(for id: UUID) -> URL {
        root.appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func assetsDirectory(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("assets", isDirectory: true)
    }

    static func prepare(_ project: Project) throws -> URL {
        let dir = directory(for: project.id)
        try FileManager.default.createDirectory(at: assetsDirectory(for: project.id), withIntermediateDirectories: true)
        try save(project)
        return dir
    }

    static func save(_ project: Project) throws {
        let dir = directory(for: project.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        if let script = project.script {
            try encoder.encode(script).write(to: dir.appendingPathComponent("script.json"), options: .atomic)
        }
        if let board = project.storyboard {
            try encoder.encode(board).write(to: dir.appendingPathComponent("storyboard.json"), options: .atomic)
        }
    }

    static func moviesDirectory() throws -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        let dir = movies.appendingPathComponent("ReelForge", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func exportURL(presetID: String, topic: String) throws -> URL {
        let slug = topic
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let folderName = "\(presetID)-\(slug.isEmpty ? "reel" : slug)-\(stamp)"
        let folder = try moviesDirectory().appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(slug.isEmpty ? "reel" : slug).mp4")
    }
}

enum BookmarkStore {
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
