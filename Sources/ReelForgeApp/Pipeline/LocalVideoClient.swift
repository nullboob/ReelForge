import Foundation

/// In-app LTX via official Python APIs. ComfyUI is not the sold path.
actor LocalVideoClient {
    static let shared = LocalVideoClient()

    func probe(modelsDir: String? = nil) -> Bool {
        ModelCatalog.scan(modelsDir: modelsDir).videoReady
    }

    func generateVideo(prompt: String, startImage: URL?, to url: URL, aspect: String = "9:16", seconds: Double = 3.0, modelsDir: String? = nil) async -> Bool {
        _ = startImage
        return InferClient.generateVideo(prompt: prompt, to: url, aspect: aspect, seconds: seconds, modelsDir: modelsDir)
    }
}
