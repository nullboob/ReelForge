import Foundation

/// First beat must be a hook: on-screen claim + VO start + picture change.
/// Logo, whoosh, “welcome back”, and music-only opens are rejected.
public enum HookRules {
    public static func isForbiddenOpen(_ text: String) -> Bool {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if spoken.isEmpty { return true }
        let needles = [
            "welcome back",
            "welcome to",
            "hey guys",
            "what's up",
            "whats up",
            "in this video",
            "today we",
            "let's talk about",
            "let us talk",
            "thanks for watching"
        ]
        return needles.contains { spoken.hasPrefix($0) }
    }
}
