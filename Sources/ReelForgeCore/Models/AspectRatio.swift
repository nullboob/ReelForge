import Foundation

public enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case vertical = "9:16"
    case landscape = "16:9"
    case square = "1:1"

    public var displayName: String { rawValue }

    public var pixelSize: (width: Int, height: Int) {
        switch self {
        case .vertical: return (1080, 1920)
        case .landscape: return (1920, 1080)
        case .square: return (1080, 1080)
        }
    }

    public var fraction: Double {
        Double(pixelSize.width) / Double(pixelSize.height)
    }
}
