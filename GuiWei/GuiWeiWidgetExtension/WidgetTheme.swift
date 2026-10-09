import SwiftUI

/// 扩展里的颜色工具（App 侧的同名方法在 Theme.swift 里，扩展不能直接引用）
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = 0.18; g = 0.37; b = 0.64
        }
        self.init(red: r, green: g, blue: b)
    }
}

enum WidgetTheme {
    static let ink = Color(hex: "1B366B")
    static let accent = Color(hex: "FFB86B")
    static let cardBackground = Color(hex: "12233F")
}
