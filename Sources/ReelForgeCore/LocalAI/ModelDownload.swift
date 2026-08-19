import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum ModelDownload {
    public static func modelsRoot(override: String? = nil) -> URL {
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("ReelForge/models", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/ReelForge/models")
    }

    public static func destination(for file: ModelManifestFile, modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(file.dest)
    }

    public static func files(for pack: SetupPack, in manifest: ModelManifest) -> [ModelManifestFile] {
        let ids = Set(manifest.packs.first { $0.id == pack.rawValue }?.fileIds ?? [])
        return manifest.files.filter { $0.pack == pack.rawValue || ids.contains($0.id) }
    }

    public static func downloadable(_ files: [ModelManifestFile]) -> [ModelManifestFile] {
        files.filter { $0.urls.contains { !$0.isEmpty } }
    }

    public static func verifyChecksum(at url: URL, expected: String) throws -> Bool {
        let trimmed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return try sha256Hex(of: url).caseInsensitiveCompare(trimmed) == .orderedSame
    }

    public static func sha256Hex(of url: URL) throws -> String {
        #if canImport(CryptoKit)
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return try sha256ViaCommand(url)
        #endif
    }

    private static func sha256ViaCommand(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.isExecutableFile(atPath: "/usr/bin/sha256sum") ? "/usr/bin/sha256sum" : "/bin/sha256sum")
        process.arguments = [url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let hex = text.split(separator: " ").first.map(String.init) ?? ""
        if hex.count != 64 { throw ModelDownloadError.checksumUnavailable }
        return hex
    }
}

public enum ModelDownloadError: Error, Equatable {
    case checksumUnavailable
}
