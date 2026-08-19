import Foundation

struct ComfyProbe: Equatable, Sendable {
    var up = false
    var ltx = false
    var wan = false
    var qwen = false
    var url = ComfyWorkflows.defaultURL
    var models: [String] = []
}

actor ComfyClient {
    static let shared = ComfyClient()

    func probe(url: String? = nil) async -> ComfyProbe {
        let root = Self.baseURL(url)
        var empty = ComfyProbe(url: root)
        if ProcessInfo.processInfo.environment["REELFORGE_SKIP_COMFY"] == "1" {
            return empty
        }
        guard let endpoint = URL(string: "\(root)/system_stats") else { return empty }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 1.6
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode < 500
        else { return empty }
        let names = await listModelNames(root: root)
        let blob = names.joined(separator: " ").lowercased()
        var ltx = blob.contains("ltx-2.3") || blob.contains("ltx2.3") || blob.contains("distilled-lora-384") || blob.contains("ltx")
        var wan = blob.contains("wan2.2") || blob.contains("wan-2.2") || blob.contains("wan22") || blob.contains("lightx2v")
        var qwen = blob.contains("qwen")
        if names.isEmpty {
            ltx = true
            wan = true
            qwen = true
        }
        empty = ComfyProbe(up: true, ltx: ltx, wan: wan, qwen: qwen, url: root, models: Array(names.prefix(48)))
        return empty
    }

    func generateVideo(
        prompt: String,
        to dest: URL,
        kind: LocalGenKind,
        aspect: String,
        seconds: Double,
        url: String? = nil,
        settings: [String: String] = [:]
    ) async -> Bool {
        guard kind != .qwen else { return false }
        if ProcessInfo.processInfo.environment["REELFORGE_SKIP_COMFY"] == "1" { return false }
        let size = ModelCatalog.alignedSize(
            width: aspect == "16:9" ? 1920 : (aspect == "1:1" ? 1080 : 1080),
            height: aspect == "16:9" ? 1080 : (aspect == "1:1" ? 1080 : 1920)
        )
        let frames = ModelCatalog.frameCount(seconds: FootageLadder.clampClipSeconds(seconds))
        let mapping: [String: Any] = [
            "PROMPT": prompt,
            "NEGATIVE": ComfyWorkflows.negative,
            "WIDTH": size.0,
            "HEIGHT": size.1,
            "FRAMES": frames,
            "SEED": Int.random(in: 1...2_000_000_000),
            "CKPT": settings[kind == .ltx ? "ltxCkpt" : "wanCkpt"] ?? ComfyWorkflows.defaultModels[kind == .ltx ? "ltxCkpt" : "wanCkpt"] ?? "",
            "LORA": settings[kind == .ltx ? "ltxLora" : "wanLora"] ?? ComfyWorkflows.defaultModels[kind == .ltx ? "ltxLora" : "wanLora"] ?? "",
            "CLIP": settings["wanClip"] ?? ComfyWorkflows.defaultModels["wanClip"] ?? "",
            "VAE": settings["wanVae"] ?? ComfyWorkflows.defaultModels["wanVae"] ?? ""
        ]
        guard let workflow = try? ComfyWorkflows.load(kind == .ltx ? "ltx-fast" : "wan-quality") else { return false }
        let filled = ComfyWorkflows.fillTemplate(workflow, mapping: mapping)
        return await run(filled, dest: dest, url: Self.baseURL(url ?? settings["comfyUrl"]), timeout: FootageLadder.timeoutSeconds(for: kind))
    }

    func generateImage(
        prompt: String,
        to dest: URL,
        aspect: String,
        url: String? = nil,
        settings: [String: String] = [:]
    ) async -> Bool {
        if ProcessInfo.processInfo.environment["REELFORGE_SKIP_COMFY"] == "1" { return false }
        let size = ModelCatalog.alignedSize(
            width: aspect == "16:9" ? 1920 : (aspect == "1:1" ? 1080 : 1080),
            height: aspect == "16:9" ? 1080 : (aspect == "1:1" ? 1080 : 1920)
        )
        let mapping: [String: Any] = [
            "PROMPT": prompt,
            "NEGATIVE": ComfyWorkflows.negative,
            "WIDTH": size.0,
            "HEIGHT": size.1,
            "SEED": Int.random(in: 1...2_000_000_000),
            "CKPT": settings["qwenCkpt"] ?? ComfyWorkflows.defaultModels["qwenCkpt"] ?? "",
            "LORA": settings["qwenLora"] ?? ComfyWorkflows.defaultModels["qwenLora"] ?? "",
            "CLIP": settings["qwenClip"] ?? ComfyWorkflows.defaultModels["qwenClip"] ?? "",
            "VAE": settings["qwenVae"] ?? ComfyWorkflows.defaultModels["qwenVae"] ?? ""
        ]
        guard let workflow = try? ComfyWorkflows.load("qwen-image") else { return false }
        let filled = ComfyWorkflows.fillTemplate(workflow, mapping: mapping)
        return await run(filled, dest: dest, url: Self.baseURL(url ?? settings["comfyUrl"]), timeout: FootageLadder.timeoutSeconds(for: .qwen))
    }

    static func storedSettings() -> [String: String] {
        let defaults = UserDefaults.standard
        var out: [String: String] = [:]
        for key in ComfyWorkflows.defaultModels.keys {
            if let value = defaults.string(forKey: "reelforge.\(key)"), !value.isEmpty {
                out[key] = value
            }
        }
        if let url = defaults.string(forKey: "reelforge.comfyUrl"), !url.isEmpty {
            out["comfyUrl"] = url
        }
        return out
    }

    static func persistDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "reelforge.comfyUrl") == nil {
            defaults.set(ComfyWorkflows.defaultURL, forKey: "reelforge.comfyUrl")
        }
        if defaults.string(forKey: "reelforge.localMode") == nil {
            defaults.set(LocalGenMode.stockFirst.rawValue, forKey: "reelforge.localMode")
        }
        for (key, value) in ComfyWorkflows.defaultModels where defaults.string(forKey: "reelforge.\(key)") == nil {
            if key == "ideogramCkpt" { continue }
            defaults.set(value, forKey: "reelforge.\(key)")
        }
    }

    static func baseURL(_ raw: String?) -> String {
        let value = (raw?.isEmpty == false ? raw : nil)
            ?? ProcessInfo.processInfo.environment["REELFORGE_COMFY_URL"]
            ?? UserDefaults.standard.string(forKey: "reelforge.comfyUrl")
            ?? ComfyWorkflows.defaultURL
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func listModelNames(root: String) async -> [String] {
        var names: [String] = []
        for path in [
            "/models/checkpoints", "/models/diffusion_models", "/models/loras",
            "/models/text_encoders", "/models/vae", "/models/unet"
        ] {
            guard let url = URL(string: "\(root)\(path)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { continue }
            if let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                names.append(contentsOf: list.map { "\($0)" })
            } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let models = dict["models"] as? [Any] {
                    names.append(contentsOf: models.map { "\($0)" })
                } else {
                    names.append(contentsOf: dict.keys)
                }
            }
        }
        return names
    }

    private func run(_ workflow: Any, dest: URL, url: String, timeout: Double) async -> Bool {
        guard let promptURL = URL(string: "\(url)/prompt") else { return false }
        var request = URLRequest(url: promptURL)
        request.httpMethod = "POST"
        request.timeoutInterval = max(timeout, 30)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["prompt": workflow, "client_id": UUID().uuidString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil,
              json["node_errors"] == nil,
              let promptID = json["prompt_id"] as? String
        else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        var outputs: [String: Any]?
        while Date() < deadline {
            if let historyURL = URL(string: "\(url)/history/\(promptID)"),
               let (histData, histResponse) = try? await URLSession.shared.data(from: historyURL),
               let histHTTP = histResponse as? HTTPURLResponse, histHTTP.statusCode == 200,
               let hist = try? JSONSerialization.jsonObject(with: histData) as? [String: Any] {
                let entry = (hist[promptID] as? [String: Any]) ?? hist
                if let found = entry["outputs"] as? [String: Any], !found.isEmpty {
                    outputs = found
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        guard let outputs, let asset = firstAsset(outputs) else { return false }
        var components = URLComponents(string: "\(url)/view")
        components?.queryItems = [
            URLQueryItem(name: "filename", value: asset.filename),
            URLQueryItem(name: "subfolder", value: asset.subfolder),
            URLQueryItem(name: "type", value: asset.type)
        ]
        guard let viewURL = components?.url,
              let (bytes, viewResponse) = try? await URLSession.shared.data(from: viewURL),
              let viewHTTP = viewResponse as? HTTPURLResponse, viewHTTP.statusCode == 200,
              bytes.count >= 400
        else { return false }
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: dest)
            return FileManager.default.fileExists(atPath: dest.path)
        } catch {
            return false
        }
    }

    private func firstAsset(_ outputs: [String: Any]) -> (filename: String, subfolder: String, type: String)? {
        for node in outputs.values {
            guard let dict = node as? [String: Any] else { continue }
            for key in ["gifs", "videos", "images"] {
                if let items = dict[key] as? [[String: Any]], let first = items.first {
                    return (
                        first["filename"] as? String ?? "",
                        first["subfolder"] as? String ?? "",
                        first["type"] as? String ?? "output"
                    )
                }
            }
        }
        return nil
    }
}
