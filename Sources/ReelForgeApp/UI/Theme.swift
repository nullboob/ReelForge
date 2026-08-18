import SwiftUI

enum RFTheme {
    static let bg = Color(red: 0.045, green: 0.045, blue: 0.055)
    static let surface = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let elevated = Color(red: 0.125, green: 0.125, blue: 0.15)
    static let border = Color.white.opacity(0.08)
    static let text = Color(red: 0.96, green: 0.94, blue: 0.91)
    static let muted = Color(red: 0.55, green: 0.53, blue: 0.58)
    static let accent = Color(red: 1.0, green: 0.30, blue: 0.43)
    static let gold = Color(red: 0.91, green: 0.76, blue: 0.60)
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 6 { s.append("FF") }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}

extension View {
    func rfCard(radius: CGFloat = 16) -> some View {
        background(RFTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(RFTheme.border, lineWidth: 1)
            )
    }
}
