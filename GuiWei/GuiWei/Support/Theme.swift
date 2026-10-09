import SwiftUI
import UIKit

/// 全局视觉常量。所有界面从这里取值，保证间距、圆角、字体一致。
enum Theme {
    // MARK: - 间距（只用 4 的倍数）
    static let gapXS: CGFloat = 4
    static let gapS: CGFloat = 8
    static let gapM: CGFloat = 12
    static let gapL: CGFloat = 16
    static let gapXL: CGFloat = 24

    // MARK: - 圆角（R 角统一收在这里）
    /// 角标、胶囊之外的方形小标签
    static let radiusChip: CGFloat = 12
    /// 缩略图、小卡片
    static let radiusSmall: CGFloat = 12
    /// 内容卡片、大图
    static let radiusCard: CGFloat = 20
    /// 按钮
    static let radiusButton: CGFloat = 14
    /// 弹出的 sheet（iOS 自己会给圆角，这里统一加大一点）
    static let radiusSheet: CGFloat = 28

    // MARK: - 尺寸
    static let thumbSize: CGFloat = 56
    static let heroHeight: CGFloat = 220

    // MARK: - 状态色
    static func color(for state: ExpiryState) -> Color {
        switch state {
        case .none: return .secondary
        case .safe: return .green
        case .soon: return .orange
        case .expired: return .red
        }
    }

    static func color(for due: LoanDueState) -> Color {
        switch due {
        case .noDue, .onTrack: return .secondary
        case .dueSoon: return .orange
        case .overdue: return .red
        }
    }
}

// MARK: - 字体

/// 关于字体：iOS 上 SwiftUI 的语义字号默认就是苹果自家字体——
/// 中文走「苹方 PingFang SC」，拉丁字母与数字走「SF Pro」。
/// 这里额外做两件事：
/// 1. 数字统一改用 SF Pro Rounded（`.rounded` 设计），这是苹果自家 App
///    （健身、健康、天气）里数字部分的常见做法，观感更柔和；
/// 2. 仍然使用语义字号，因此「文字大小」辅助功能设置依旧生效，
///    不像 `.system(size:)` 那样写死。
extension Font {
    /// 语义字号 + 圆体数字设计
    static func number(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

extension View {
    /// 数字用的字体：苹方 + SF Pro Rounded
    func numberFont(_ style: Font.TextStyle = .title2, weight: Font.Weight = .semibold) -> some View {
        font(.number(style, weight: weight))
    }

    /// 统一的主按钮形状（R 角）
    func appButtonShape() -> some View {
        buttonBorderShape(.roundedRectangle(radius: Theme.radiusButton))
    }

    /// 统一 sheet 的圆角
    func appSheetRadius() -> some View {
        presentationCornerRadius(Theme.radiusSheet)
    }
}

extension Color {
    /// 从十六进制字符串构造颜色，模型里存的是字符串，避免直接存 Color
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

extension Date {
    /// 列表里显示"今天 / 昨天 / 具体日期"，比直接显示时间戳更好读
    var friendlyDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "今天" }
        if cal.isDateInYesterday(self) { return "昨天" }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
