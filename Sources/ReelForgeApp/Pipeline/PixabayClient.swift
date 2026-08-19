import Foundation

struct PixabayClip: Sendable {
    var id: Int
    var videoURL: URL
    var user: String
    var pageURL: String
}

actor PixabayClient {
    static let shared = PixabayClient()

    func search(
        query: String,
        accessKey: String,
        portrait: Bool,
        page: Int = 1,
        excluding: Set<Int> = []
    ) async -> PixabayClip? {
        let cleaned = StockQueryHygiene.specificQuery(query)
        var components = URLComponents(string: "https://pixabay.com/api/videos/")
        components?.queryItems = [
            URLQueryItem(name: "key", value: accessKey),
            URLQueryItem(name: "q", value: cleaned),
            URLQueryItem(name: "per_page", value: "12"),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "video_type", value: "film"),
            URLQueryItem(name: "safesearch", value: "true"),
            URLQueryItem(name: "orientation", value: portrait ? "vertical" : "horizontal")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]]
        else { return nil }

        let unused = hits.filter { hit in
            let id = hit["id"] as? Int ?? 0
            return id > 0 && !excluding.contains(id)
        }
        guard let first = unused.first ?? hits.first else { return nil }
        let videos = first["videos"] as? [String: Any] ?? [:]
        let preferred = (videos["large"] as? [String: Any])
            ?? (videos["medium"] as? [String: Any])
            ?? (videos["small"] as? [String: Any])
        guard let link = preferred?["url"] as? String, let videoURL = URL(string: link) else { return nil }
        return PixabayClip(
            id: first["id"] as? Int ?? 0,
            videoURL: videoURL,
            user: (first["user"] as? String) ?? "Pixabay contributor",
            pageURL: (first["pageURL"] as? String) ?? "https://pixabay.com"
        )
    }

    func download(_ clip: PixabayClip, to url: URL) async -> Bool {
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
