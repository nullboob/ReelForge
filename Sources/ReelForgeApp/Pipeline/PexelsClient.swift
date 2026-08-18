import Foundation

struct PexelsClip: Sendable {
    var id: Int
    var videoURL: URL
    var photographer: String
    var photographerURL: String
    var pageURL: String
}

actor PexelsClient {
    static let shared = PexelsClient()

    func search(query: String, accessKey: String, portrait: Bool) async -> PexelsClip? {
        var components = URLComponents(string: "https://api.pexels.com/videos/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "8"),
            URLQueryItem(name: "orientation", value: portrait ? "portrait" : "landscape")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(accessKey, forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videos = json["videos"] as? [[String: Any]],
              let first = videos.randomElement() ?? videos.first
        else { return nil }

        let files = (first["video_files"] as? [[String: Any]]) ?? []
        let preferred = files.first { ($0["quality"] as? String) == "hd" } ?? files.first
        guard let link = preferred?["link"] as? String, let videoURL = URL(string: link) else { return nil }
        let user = first["user"] as? [String: Any]
        return PexelsClip(
            id: first["id"] as? Int ?? 0,
            videoURL: videoURL,
            photographer: (user?["name"] as? String) ?? "Pexels contributor",
            photographerURL: (user?["url"] as? String) ?? "https://www.pexels.com",
            pageURL: (first["url"] as? String) ?? "https://www.pexels.com"
        )
    }

    func download(_ clip: PexelsClip, to url: URL) async -> Bool {
        guard let (data, response) = try? await URLSession.shared.data(from: clip.videoURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count > 400
        else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
