import Foundation

/// Optional local video generators (ComfyUI / custom `/video`). Never fakes a cloud model.
actor LocalVideoClient {
    static let shared = LocalVideoClient()

    func probe() async -> Bool {
        for raw in [
            "http://127.0.0.1:8188/system_stats",
            "http://127.0.0.1:8188/",
            "http://127.0.0.1:7860/video"
        ] {
            guard let url = URL(string: raw) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.6
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<500).contains(http.statusCode) {
                return true
            }
        }
        return false
    }

    func generateVideo(prompt: String, to url: URL) async -> Bool {
        _ = prompt
        _ = url
        return false
    }
}
