import Foundation

public struct ModelSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var ready: Bool
    public var path: String?

    public init(id: String, name: String, kind: String, ready: Bool, path: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.ready = ready
        self.path = path
    }
}

public struct ModelScan: Codable, Equatable, Sendable {
    public var slots: [ModelSlot]
    public var videoReady: Bool
    public var imageReady: Bool
    public var anyReady: Bool
    public var scannedFiles: Int
    public var modelsDir: String

    public init(
        slots: [ModelSlot],
        videoReady: Bool,
        imageReady: Bool,
        anyReady: Bool,
        scannedFiles: Int,
        modelsDir: String
    ) {
        self.slots = slots
        self.videoReady = videoReady
        self.imageReady = imageReady
        self.anyReady = anyReady
        self.scannedFiles = scannedFiles
        self.modelsDir = modelsDir
    }
}

public enum ModelCatalog {
    public static let specs: [(id: String, name: String, kind: String, patterns: [String])] = [
        ("ltx-distilled", "LTX-2.3 22B distilled", "video", ["ltx-2.3-22b-distilled", "ltx.*22b.*distill.*\\.safetensors"]),
        ("ltx-lora", "LTX distilled LoRA", "video", ["ltx.*lora", "distill.*lora.*ltx"]),
        ("gemma-encoder", "Gemma text encoder", "video", ["gemma"]),
        ("ltx-gguf", "LTX Q5 GGUF", "video", ["ltx.*\\.gguf", "q5.*\\.gguf", "\\.gguf"]),
        ("qwen-image", "Qwen Image", "image", ["qwen.*image", "qwen_image"]),
        ("qwen-lightning", "Qwen Lightning 8-step LoRA", "image", ["lightning", "qwen.*lora"]),
        ("wan-22", "Wan 2.2 (optional later)", "video-quality", ["wan2\\.2", "wan-2\\.2", "wan22"]),
        ("lightx2v", "LightX2V 4-step (optional later)", "video-quality", ["lightx2v", "light-x2v"])
    ]

    public static func defaultRoots(modelsDir: String?) -> [URL] {
        var roots: [URL] = []
        if let extra = ProcessInfo.processInfo.environment["REELFORGE_MODEL_SCAN_ROOTS"], !extra.isEmpty {
            let separator: Character = extra.contains(";") ? ";" : ":"
            roots.append(contentsOf: extra.split(separator: separator).map { URL(fileURLWithPath: String($0)) })
        }
        if let modelsDir, !modelsDir.isEmpty {
            roots.append(URL(fileURLWithPath: modelsDir))
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("ReelForge/models"))
        }
        roots.append(URL(fileURLWithPath: "E:/ComfyUI_windows_portable_nvidia/ComfyUI/models"))
        roots.append(URL(fileURLWithPath: "D:/"))
        return unique(roots)
    }

    public static func scan(modelsDir: String? = nil, roots: [URL]? = nil) -> ModelScan {
        let files = collect(from: roots ?? defaultRoots(modelsDir: modelsDir))
        let slots: [ModelSlot] = specs.map { spec in
            let match = files.first { file in
                spec.patterns.contains { pattern in
                    file.lastPathComponent.range(of: pattern, options: .regularExpression) != nil
                }
            }
            return ModelSlot(
                id: spec.id,
                name: spec.name,
                kind: spec.kind,
                ready: match != nil,
                path: match?.path
            )
        }
        let videoReady = slots.contains { ($0.id == "ltx-distilled" || $0.id == "ltx-gguf") && $0.ready }
        let imageReady = slots.contains { $0.id == "qwen-image" && $0.ready }
        return ModelScan(
            slots: slots,
            videoReady: videoReady,
            imageReady: imageReady,
            anyReady: videoReady || imageReady,
            scannedFiles: files.count,
            modelsDir: modelsDir ?? ""
        )
    }

    public static func alignedSize(width: Int, height: Int, multiple: Int = 32) -> (Int, Int) {
        func snap(_ value: Int) -> Int {
            max(multiple, (value / multiple) * multiple)
        }
        return (snap(width), snap(height))
    }

    public static func frameCount(seconds: Double, fps: Int = 24) -> Int {
        let raw = max(9, Int((seconds * Double(fps)).rounded()))
        return ((raw + 6) / 8) * 8 + 1
    }

    private static func collect(from roots: [URL]) -> [URL] {
        var files: [URL] = []
        for root in roots {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if isDriveRoot(root) {
                files.append(contentsOf: topLevelWeights(at: root))
                files.append(contentsOf: walkWeights(at: root.appendingPathComponent("models"), maxDepth: 4))
                continue
            }
            files.append(contentsOf: walkWeights(at: root, maxDepth: 6))
        }
        return files
    }

    private static func topLevelWeights(at root: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return names.filter { ["safetensors", "gguf"].contains($0.pathExtension.lowercased()) }
    }

    private static func walkWeights(at root: URL, maxDepth: Int) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        var files: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if ["safetensors", "gguf", "bin", "pt"].contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    private static func isDriveRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        return trimmed.count == 2 && trimmed.hasSuffix(":")
    }

    private static func unique(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }
}
