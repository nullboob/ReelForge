import Foundation

public enum LocalGenMode: String, Codable, Sendable {
    case stockFirst = "stock-first"
    case localFast = "local-fast"
    case localQuality = "local-quality"
}

public enum LocalGenKind: String, Sendable {
    case ltx
    case wan
    case qwen
}

public enum FootageLadder {
    public static func parseMode(_ raw: String?) -> LocalGenMode {
        LocalGenMode(rawValue: raw ?? "") ?? .stockFirst
    }

    public static func stockBeforeLocal(_ mode: LocalGenMode) -> Bool {
        mode == .stockFirst
    }

    /// Local Fast: one LTX hook clip, Qwen stills for the rest.
    /// Local Quality: Wan for hook + two body beats, Qwen stills after that.
    public static func kind(beatIndex: Int, mode: LocalGenMode) -> LocalGenKind {
        switch mode {
        case .localQuality:
            return beatIndex <= 2 ? .wan : .qwen
        case .stockFirst, .localFast:
            return beatIndex == 0 ? .ltx : .qwen
        }
    }

    public static func timeoutSeconds(for kind: LocalGenKind) -> Double {
        switch kind {
        case .ltx: return 90
        case .wan: return 180
        case .qwen: return 20
        }
    }

    public static func credit(for kind: LocalGenKind) -> String {
        switch kind {
        case .ltx: return "LTX-2.3 local"
        case .wan: return "Wan 2.2 local"
        case .qwen: return "Qwen Image local"
        }
    }

    public static func clampClipSeconds(_ seconds: Double) -> Double {
        min(4, max(2, seconds))
    }

    public static func renderPrompt(text: String, styleSuffix: String, aspect: String = "9:16") -> String {
        let cleaned = StockQueryHygiene.specificQuery(text.isEmpty ? "handheld documentary texture" : text)
        let suffix = styleSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned), vertical \(aspect) photoreal footage, natural light, no text, no captions, no logo, no watermark, no title card. \(suffix)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
