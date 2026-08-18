import Foundation

public enum CaptionSafeArea {
    /// YouTube Shorts UI eats the right rail and the lower third.
    /// Keep ~12% bottom and ~18% right clear on 9:16; milder insets on 16:9.
    public static func rect(width: Double, height: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let portrait = width < height
        let left = width * 0.08
        let right = width * (portrait ? 0.18 : 0.08)
        let bottom = height * 0.12
        let top = height * 0.10
        return (left, bottom, max(1, width - left - right), max(1, height - bottom - top))
    }

    public static func maxWords(forPresetID id: String, requested: Int) -> Int {
        if id == "viral-hook" {
            return min(max(requested, 1), 7)
        }
        return max(1, requested)
    }
}
