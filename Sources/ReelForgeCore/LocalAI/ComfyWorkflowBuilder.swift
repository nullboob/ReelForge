import Foundation

public struct ComfyCapabilities: Equatable, Sendable {
    public var online: Bool
    public var canTextToImage: Bool
    public var canImageToVideo: Bool
    public var hasLTX: Bool
    public var hasQwenImage: Bool
    public var checkpoint: String?
    public var sampler: String?
    public var scheduler: String?
    public var detail: String

    public init(
        online: Bool = false,
        canTextToImage: Bool = false,
        canImageToVideo: Bool = false,
        hasLTX: Bool = false,
        hasQwenImage: Bool = false,
        checkpoint: String? = nil,
        sampler: String? = nil,
        scheduler: String? = nil,
        detail: String = ""
    ) {
        self.online = online
        self.canTextToImage = canTextToImage
        self.canImageToVideo = canImageToVideo
        self.hasLTX = hasLTX
        self.hasQwenImage = hasQwenImage
        self.checkpoint = checkpoint
        self.sampler = sampler
        self.scheduler = scheduler
        self.detail = detail
    }
}

public enum ComfyWorkflowBuilder {
    public static let defaultBaseURL = "http://127.0.0.1:8188"

    public static func capabilities(objectInfo: [String: Any], online: Bool) -> ComfyCapabilities {
        let classes = Set(objectInfo.keys)
        let hasLoader = classes.contains("CheckpointLoaderSimple")
        let hasEncode = classes.contains("CLIPTextEncode")
        let hasSampler = classes.contains("KSampler")
        let hasLatent = classes.contains("EmptyLatentImage")
        let hasDecode = classes.contains("VAEDecode")
        let hasSave = classes.contains("SaveImage")
        let canT2I = hasLoader && hasEncode && hasSampler && hasLatent && hasDecode && hasSave

        let hasLTX = classes.contains(where: { name in
            let lower = name.lowercased()
            return lower.contains("ltxv") || lower.contains("ltxvideo") || lower.contains("ltx-video")
        })
        let hasQwen = classes.contains(where: { $0.lowercased().contains("qwen") && $0.lowercased().contains("image") })
        let hasI2VNode = classes.contains(where: { name in
            let lower = name.lowercased()
            return lower.contains("imgtovideo") || lower.contains("image_to_video")
                || lower.contains("img2vid") || lower.contains("ltxvimgtovideo")
        })

        let checkpoint = firstCombo(
            objectInfo["CheckpointLoaderSimple"],
            keys: ["ckpt_name"]
        ).flatMap { preferModel($0, needles: ["qwen", "ltx", "flux", "sdxl", "sd3", "realistic"]) }

        let sampler = firstCombo(objectInfo["KSampler"], keys: ["sampler_name"])
            .flatMap { preferModel($0, needles: ["euler", "dpmpp"]) }
        let scheduler = firstCombo(objectInfo["KSampler"], keys: ["scheduler"])
            .flatMap { preferModel($0, needles: ["normal", "simple", "karras", "sgm"]) }

        var parts: [String] = []
        if canT2I { parts.append("T2I") }
        if hasLTX { parts.append("LTX") }
        if hasQwen { parts.append("Qwen Image") }
        if hasI2VNode { parts.append("I2V") }
        if let checkpoint { parts.append(checkpoint) }

        return ComfyCapabilities(
            online: online,
            canTextToImage: canT2I,
            canImageToVideo: hasLTX || hasI2VNode,
            hasLTX: hasLTX,
            hasQwenImage: hasQwen,
            checkpoint: checkpoint,
            sampler: sampler,
            scheduler: scheduler,
            detail: parts.isEmpty ? "8188 up" : parts.joined(separator: " · ")
        )
    }

    public static func textToImagePrompt(
        text: String,
        width: Int,
        height: Int,
        capabilities: ComfyCapabilities
    ) -> [String: Any]? {
        guard capabilities.canTextToImage,
              let ckpt = capabilities.checkpoint
        else { return nil }
        let w = aligned(width, max: 768)
        let h = aligned(height, max: 1344)
        let sampler = capabilities.sampler ?? "euler"
        let scheduler = capabilities.scheduler ?? "normal"
        let seed = Int.random(in: 1...9_000_000)
        return [
            "3": [
                "class_type": "KSampler",
                "inputs": [
                    "seed": seed,
                    "steps": 18,
                    "cfg": 6.5,
                    "sampler_name": sampler,
                    "scheduler": scheduler,
                    "denoise": 1,
                    "model": ["4", 0],
                    "positive": ["6", 0],
                    "negative": ["7", 0],
                    "latent_image": ["5", 0]
                ]
            ],
            "4": [
                "class_type": "CheckpointLoaderSimple",
                "inputs": ["ckpt_name": ckpt]
            ],
            "5": [
                "class_type": "EmptyLatentImage",
                "inputs": ["width": w, "height": h, "batch_size": 1]
            ],
            "6": [
                "class_type": "CLIPTextEncode",
                "inputs": ["text": text, "clip": ["4", 1]]
            ],
            "7": [
                "class_type": "CLIPTextEncode",
                "inputs": [
                    "text": "blurry, watermark, text overlay, low quality, deformed",
                    "clip": ["4", 1]
                ]
            ],
            "8": [
                "class_type": "VAEDecode",
                "inputs": ["samples": ["3", 0], "vae": ["4", 2]]
            ],
            "9": [
                "class_type": "SaveImage",
                "inputs": ["filename_prefix": "ReelForge", "images": ["8", 0]]
            ]
        ]
    }

    /// Injects a text prompt (and optional LoadImage filename) into an API-format workflow.
    public static func inject(into workflow: [String: Any], prompt: String, imageFilename: String?) -> [String: Any] {
        var next = workflow
        var filledPrompt = false
        for (key, value) in workflow {
            guard var node = value as? [String: Any] else { continue }
            let type = (node["class_type"] as? String) ?? ""
            var inputs = (node["inputs"] as? [String: Any]) ?? [:]
            if type == "CLIPTextEncode" || type.lowercased().contains("textencode") {
                if !filledPrompt {
                    inputs["text"] = prompt
                    filledPrompt = true
                }
            }
            if let imageFilename,
               type == "LoadImage" || type.lowercased().contains("loadimage") {
                inputs["image"] = imageFilename
            }
            node["inputs"] = inputs
            next[key] = node
        }
        return next
    }

    public static func firstOutputFile(from history: [String: Any], kinds: [String] = ["images", "gifs", "videos"]) -> (filename: String, subfolder: String, type: String)? {
        let outputs: [String: Any]
        if let nested = history["outputs"] as? [String: Any] {
            outputs = nested
        } else if let first = history.values.compactMap({ $0 as? [String: Any] }).first,
                  let nested = first["outputs"] as? [String: Any] {
            outputs = nested
        } else {
            return nil
        }
        for (_, value) in outputs {
            guard let node = value as? [String: Any] else { continue }
            for kind in kinds {
                if let files = node[kind] as? [[String: Any]],
                   let file = files.first,
                   let name = file["filename"] as? String {
                    return (
                        name,
                        file["subfolder"] as? String ?? "",
                        file["type"] as? String ?? "output"
                    )
                }
            }
        }
        return nil
    }

    public static func preferModel(_ names: [String], needles: [String]) -> String? {
        for needle in needles {
            if let match = names.first(where: { $0.lowercased().contains(needle) }) {
                return match
            }
        }
        return names.first
    }

    public static func firstCombo(_ node: Any?, keys: [String]) -> [String]? {
        guard let node = node as? [String: Any] else { return nil }
        let input = (node["input"] as? [String: Any]) ?? [:]
        let required = (input["required"] as? [String: Any]) ?? [:]
        let optional = (input["optional"] as? [String: Any]) ?? [:]
        for key in keys {
            if let values = comboValues(required[key]) ?? comboValues(optional[key]) {
                return values
            }
        }
        return nil
    }

    public static func comboValues(_ raw: Any?) -> [String]? {
        if let list = raw as? [Any], let first = list.first as? [String] {
            return first
        }
        if let list = raw as? [String] {
            return list
        }
        if let dict = raw as? [String: Any], let options = dict["options"] as? [String] {
            return options
        }
        return nil
    }

    public static func aligned(_ value: Int, max ceiling: Int) -> Int {
        let clamped = min(Swift.max(value, 256), ceiling)
        return (clamped / 8) * 8
    }
}
