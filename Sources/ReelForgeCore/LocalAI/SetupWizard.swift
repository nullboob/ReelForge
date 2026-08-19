import Foundation

public struct HardwareSnapshot: Equatable, Sendable {
    public var nvidia: Bool
    public var vramGB: Double
    public var appleGPU: Bool
    public var ramGB: Double
    public var diskFreeGB: Double

    public init(nvidia: Bool, vramGB: Double, appleGPU: Bool, ramGB: Double, diskFreeGB: Double) {
        self.nvidia = nvidia
        self.vramGB = vramGB
        self.appleGPU = appleGPU
        self.ramGB = ramGB
        self.diskFreeGB = diskFreeGB
    }
}

public enum SetupPack: String, Codable, Sendable {
    case instant
    case fastImage = "fast-image"
    case fastVideo = "fast-video"
    case qualityVideo = "quality-video"
}

public struct ModelManifestFile: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var sizeBytes: Int64
    public var urls: [String]
    public var sha256: String
    public var minVramGB: Double
    public var dest: String
    public var optional: Bool
    public var pack: String
    public var note: String
}

public struct ModelManifestPack: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sizeLabel: String
    public var summary: String
    public var fileIds: [String]
    public var minVramGB: Double
    public var hiddenUnlessVramGB: Double?
}

public struct ModelManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var title: String
    public var modelsDirNote: String
    public var scanRoots: [String]
    public var packs: [ModelManifestPack]
    public var files: [ModelManifestFile]
}

public enum SetupWizard {
    public static let title = "Set up ReelForge in one click"

    public static func recommend(_ hardware: HardwareSnapshot) -> SetupPack {
        if hardware.nvidia && hardware.vramGB >= 8 { return .fastVideo }
        if hardware.appleGPU { return .fastImage }
        return .instant
    }

    public static func showQuality(_ hardware: HardwareSnapshot) -> Bool {
        hardware.vramGB >= 16
    }

    public static func visiblePacks(_ hardware: HardwareSnapshot, from manifest: ModelManifest) -> [ModelManifestPack] {
        manifest.packs.filter { pack in
            guard let need = pack.hiddenUnlessVramGB else { return true }
            return hardware.vramGB >= need
        }
    }

    public static func loadManifest() throws -> ModelManifest {
        if let url = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "models"),
           let data = try? Data(contentsOf: url) {
            return try JSONDecoder().decode(ModelManifest.self, from: data)
        }
        if let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "models"),
           let data = try? Data(contentsOf: url) {
            return try JSONDecoder().decode(ModelManifest.self, from: data)
        }
        let source = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/models/manifest.json")
        return try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: source))
    }
}
