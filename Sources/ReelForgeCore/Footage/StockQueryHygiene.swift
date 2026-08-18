import Foundation

/// Skip first-page generic stock queries (office, nature, city aerial).
public enum StockQueryHygiene {
    public static let genericNeedles = [
        "office", "nature", "city aerial", "aerial city", "cityscape aerial",
        "handshake", "business meeting", "generic city", "stock office"
    ]

    public static func specificQuery(_ raw: String) -> String {
        let lower = raw.lowercased()
        if genericNeedles.contains(where: { lower.contains($0) }) {
            let words = raw.split { !$0.isLetter }.map(String.init).filter { $0.count > 4 }
            if let word = words.first(where: { candidate in
                !genericNeedles.contains { $0.contains(candidate.lowercased()) }
            }) {
                return "\(word) handheld documentary"
            }
            return "handheld documentary texture"
        }
        return raw
    }
}
