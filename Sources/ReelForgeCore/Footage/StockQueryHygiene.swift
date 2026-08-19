import Foundation

/// Skip first-page generic stock queries (office, nature, city aerial).
public enum StockQueryHygiene {
    public static let genericNeedles = [
        "office", "nature", "city aerial", "aerial city", "cityscape aerial",
        "handshake", "business meeting", "generic city", "stock office"
    ]

    private static let stop = Set([
        "this", "that", "with", "from", "your", "have", "will", "stop", "just",
        "they", "them", "then", "than", "what", "when", "where", "about", "after",
        "before", "because", "could", "should", "would", "there", "their", "these",
        "those", "into", "over", "under", "more", "most", "some", "very", "also"
    ])

    public static func specificQuery(_ raw: String) -> String {
        let nouns = raw.split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 && !stop.contains($0.lowercased()) }
        if !nouns.isEmpty {
            return nouns.prefix(3).joined(separator: " ") + " handheld closeup"
        }
        let lower = raw.lowercased()
        if genericNeedles.contains(where: { lower.contains($0) }) {
            return "handheld documentary texture"
        }
        return raw
    }

    /// Never immediately replay a clip id already used in this export.
    public static func firstUnusedID(ids: [Int], excluding: Set<Int>) -> Int? {
        ids.first { $0 > 0 && !excluding.contains($0) }
    }
}
