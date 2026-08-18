import Foundation

struct LocalAIStatus: Equatable {
    var ollama = false
    var automatic1111 = false
    var comfyUI = false
    var comfyDetail = ""
    var canComfyVideo = false
    var aceStep = false
    var mlxImage = false
    var whisper = false
    var kokoro = false
    var piper = false
    var ttsEngine = "AVSpeech"
    var ollamaModel: String?

    var anyImage: Bool { comfyUI || automatic1111 || mlxImage }
    var anyLLM: Bool { ollama }
    var anyVideo: Bool { canComfyVideo }
}

actor LocalAIClient {
    static let shared = LocalAIClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.8
        config.timeoutIntervalForResource = 1.2
        return URLSession(configuration: config)
    }()

    func probe() async -> LocalAIStatus {
        async let ollama = probeOllama()
        async let comfy = ComfyUIClient.shared.capabilities(force: true)
        async let a1111 = isUp(URL(string: "http://127.0.0.1:7860/sdapi/v1/sd-models")!)
        async let ace = ACEStepClient.shared.probe()
        async let mlx = isUp(URL(string: "http://127.0.0.1:7861/health")!)
            || isUp(URL(string: "http://127.0.0.1:8088/health")!)
        async let whisper = isUp(URL(string: "http://127.0.0.1:9000/health")!)
            || isUp(URL(string: "http://127.0.0.1:9000/")!)
        async let kokoro = isUp(URL(string: "http://127.0.0.1:8880/v1/models")!)
            || isUp(URL(string: "http://127.0.0.1:8880/")!)
        let model = await ollama
        let comfyCaps = await comfy
        let kokoroUp = await kokoro
        let tts = kokoroUp ? "Kokoro" : "AVSpeech"
        return LocalAIStatus(
            ollama: model != nil,
            automatic1111: await a1111,
            comfyUI: comfyCaps.online,
            comfyDetail: comfyCaps.detail,
            canComfyVideo: comfyCaps.canImageToVideo,
            aceStep: await ace,
            mlxImage: await mlx,
            whisper: await whisper,
            kokoro: kokoroUp,
            piper: false,
            ttsEngine: tts,
            ollamaModel: model
        )
    }

    func generateScript(topic: String, preset: Preset, model: String, durationSec: Int) async -> String? {
        await complete(
            prompt: ScriptWriter.ollamaPrompt(topic: topic, preset: preset, durationSec: durationSec),
            model: model,
            predict: durationSec >= 180 ? 700 : 280
        )
    }

    func generatePublishCopy(topic: String, script: GeneratedScript, channel: ChannelKit, model: String) async -> String? {
        await complete(
            prompt: PublishPackWriter.ollamaPrompt(topic: topic, script: script, channel: channel),
            model: model,
            predict: 220
        )
    }

    private func complete(prompt: String, model: String, predict: Int) async -> String? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.7, "num_predict": predict]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    func generateImage(prompt: String, size: (Int, Int), to url: URL) async -> Bool {
        if await ComfyUIClient.shared.generateImage(prompt: prompt, size: size, to: url) { return true }
        if await generateA1111(prompt: prompt, size: size, to: url) { return true }
        if await generateGeneric(prompt: prompt, size: size, to: url) { return true }
        return false
    }

    private func generateA1111(prompt: String, size: (Int, Int), to url: URL) async -> Bool {
        guard let endpoint = URL(string: "http://127.0.0.1:7860/sdapi/v1/txt2img") else { return false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "prompt": prompt,
            "steps": 18,
            "width": min(size.0, 768),
            "height": min(size.1, 1344),
            "cfg_scale": 6.5
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [String],
              let first = images.first,
              let imageData = Data(base64Encoded: first)
        else { return false }
        do {
            try imageData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func generateGeneric(prompt: String, size: (Int, Int), to url: URL) async -> Bool {
        for raw in ["http://127.0.0.1:7860/generate", "http://127.0.0.1:7861/generate", "http://127.0.0.1:8088/generate"] {
            guard let endpoint = URL(string: raw) else { continue }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "prompt": prompt,
                "width": size.0,
                "height": size.1
            ])
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { continue }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let b64 = json["image"] as? String,
               let imageData = Data(base64Encoded: b64) {
                try? imageData.write(to: url)
                return FileManager.default.fileExists(atPath: url.path)
            }
            if data.count > 100 {
                try? data.write(to: url)
                return true
            }
        }
        return false
    }

    private func probeOllama() async -> String? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return nil }
        let names = models.compactMap { $0["name"] as? String }
        let preferred = ["llama3.2", "llama3.1", "llama3", "qwen2.5", "mistral", "gemma2", "phi3"]
        for needle in preferred {
            if let match = names.first(where: { $0.lowercased().contains(needle) }) {
                return match
            }
        }
        return names.first
    }

    private func isUp(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.7
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<500).contains(http.statusCode)
    }
}
