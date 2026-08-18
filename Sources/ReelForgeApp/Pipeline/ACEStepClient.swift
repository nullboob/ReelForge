import Foundation

/// Optional local ACE-Step music generator. Programmatic beds stay the guaranteed path.
actor ACEStepClient {
    static let shared = ACEStepClient()

    private let probeURLs = [
        "http://127.0.0.1:7865/",
        "http://127.0.0.1:7865/config",
        "http://127.0.0.1:8001/health",
        "http://127.0.0.1:8019/health"
    ]

    private let generateURLs = [
        "http://127.0.0.1:7865/generate",
        "http://127.0.0.1:8001/generate",
        "http://127.0.0.1:8001/v1/music",
        "http://127.0.0.1:8019/generate"
    ]

    func probe() async -> Bool {
        for raw in probeURLs {
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

    func generateBed(mood: String, bpm: Int, to url: URL) async -> Bool {
        let prompt = "Instrumental \(mood) bed, \(bpm) BPM, no vocals, clean loop, original-safe electronic score"
        for raw in generateURLs {
            guard let endpoint = URL(string: raw) else { continue }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 45
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "prompt": prompt,
                "lyrics": "",
                "duration": 8,
                "bpm": bpm,
                "infer_step": 30
            ])
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count > 200
            else { continue }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let b64 = json["audio"] as? String ?? json["wav"] as? String,
                   let decoded = Data(base64Encoded: b64) {
                    try? decoded.write(to: url)
                    return FileManager.default.fileExists(atPath: url.path)
                }
                if let path = json["path"] as? String, FileManager.default.fileExists(atPath: path) {
                    try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
                    return FileManager.default.fileExists(atPath: url.path)
                }
            }
            if looksLikeAudio(data) {
                try? data.write(to: url)
                return true
            }
        }
        return false
    }

    private func looksLikeAudio(_ data: Data) -> Bool {
        guard data.count > 12 else { return false }
        let head = data.prefix(4)
        if head == Data("RIFF".utf8) || head == Data("fLaC".utf8) || head == Data("OggS".utf8) {
            return true
        }
        if data[0] == 0xFF, data[1] & 0xE0 == 0xE0 { return true }
        return false
    }
}
