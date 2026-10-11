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
    static let cardBackground = Color(hex: "12233F")

    /// 到期：橙红，表示"要处理"
    static let expiryAccent = Color(hex: "FF8A4C")
    /// 归还：暖黄，表示"在外面"
    static let loanAccent = Color(hex: "FFC46B")
    /// 已经逾期：红
    static let overdueAccent = Color(hex: "FF6B6B")
    /// 一切正常
    static let doneAccent = Color(hex: "5BD08A")

    /// 依据活动类型与剩余天数取强调色
    static func accent(for kind: GuiWeiActivityAttributes.Kind, daysLeft: Int?) -> Color {
        if let days = daysLeft, days < 0 { return overdueAccent }
        return kind == .expiry ? expiryAccent : loanAccent
    }
}
