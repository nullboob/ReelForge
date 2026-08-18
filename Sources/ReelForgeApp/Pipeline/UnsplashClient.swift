import Foundation

struct UnsplashPhoto: Sendable {
    var id: String
    var imageURL: URL
    var photographer: String
    var photographerURL: String
    var pageURL: String
}

enum UnsplashClientError: Error {
    case missingKey
    case badResponse
}

actor UnsplashClient {
    static let shared = UnsplashClient()

    func search(query: String, accessKey: String, portrait: Bool) async -> UnsplashPhoto? {
        var components = URLComponents(string: "https://api.unsplash.com/search/photos")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "8"),
            URLQueryItem(name: "orientation", value: portrait ? "portrait" : "landscape")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.randomElement() ?? results.first
        else { return nil }

        let urls = first["urls"] as? [String: Any]
        let raw = (urls?["regular"] as? String) ?? (urls?["small"] as? String)
        guard let raw, let imageURL = URL(string: raw) else { return nil }
        let user = first["user"] as? [String: Any]
        let name = (user?["name"] as? String) ?? "Unsplash photographer"
        let profile = (user?["links"] as? [String: Any])?["html"] as? String ?? "https://unsplash.com"
        let page = (first["links"] as? [String: Any])?["html"] as? String ?? "https://unsplash.com"
        return UnsplashPhoto(
            id: first["id"] as? String ?? UUID().uuidString,
            imageURL: imageURL,
            photographer: name,
            photographerURL: profile,
            pageURL: page
        )
    }

    func download(_ photo: UnsplashPhoto, to url: URL) async -> Bool {
        guard let (data, response) = try? await URLSession.shared.data(from: photo.imageURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count > 80
        else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
