import Foundation

public enum CaptionSafeArea {
    /// Shorts / Reels / TikTok chrome insets. Watermarks and cards use this.
    public static func rect(width: Double, height: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let portrait = width < height
        let left = width * 0.08
        let right = width * (portrait ? 0.18 : 0.08)
        let bottom = height * 0.18
        let top = height * 0.12
        return (left, bottom, max(1, width - left - right), max(1, height - bottom - top))
    }

    /// Caption block for 1080×1920 lives around y 700–1360. Other sizes scale from that.
    public static func captionBand(width: Double, height: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let chrome = rect(width: width, height: height)
        let top = height * (700.0 / 1920.0)
        let bottom = height * (1360.0 / 1920.0)
        return (chrome.x, top, chrome.width, max(1, bottom - top))
    }

    public static func captionCenterY(height: Double) -> Double {
        height * ((700.0 + 1360.0) / 2.0 / 1920.0)
    }

    /// Research word clock: 2–4 words per card (1 only for single-word styles).
    public static func maxWords(forPresetID id: String, requested: Int) -> Int {
        _ = id
        return max(1, min(requested, 4))
    }
}
