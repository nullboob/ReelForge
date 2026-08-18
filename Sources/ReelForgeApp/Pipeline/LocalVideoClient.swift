import Foundation

/// Local video generators. ComfyUI on 8188 is the real path (LTX / user I2V workflow).
/// Never fakes a cloud video model. If the exact graph is missing, skip and keep exporting.
actor LocalVideoClient {
    static let shared = LocalVideoClient()

    func probe() async -> Bool {
        let caps = await ComfyUIClient.shared.capabilities()
        if caps.online { return true }
        for raw in ["http://127.0.0.1:7860/video"] {
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

    func generateVideo(prompt: String, startImage: URL?, to url: URL) async -> Bool {
        if await ComfyUIClient.shared.generateVideo(prompt: prompt, startImage: startImage, to: url) {
            return true
        }
        return false
    }
}
