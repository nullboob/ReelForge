import Foundation

public enum CaptionSafeArea {
    /// Shorts / Reels / TikTok chrome: keep captions above the bottom ~18%
    /// and below the top ~12%, plus ~18% right on 9:16.
    public static func rect(width: Double, height: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let portrait = width < height
        let left = width * 0.08
        let right = width * (portrait ? 0.18 : 0.08)
        let bottom = height * 0.18
        let top = height * 0.12
        return (left, bottom, max(1, width - left - right), max(1, height - bottom - top))
    }

    public static func maxWords(forPresetID id: String, requested: Int) -> Int {
        if id == "viral-hook" {
            return min(max(requested, 3), 6)
        }
        return max(1, requested)
    }
}
