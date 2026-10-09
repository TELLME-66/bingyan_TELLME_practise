import SwiftUI

/// 外观偏好。
///
/// 默认**跟随系统**——这是苹果平台的惯例：系统开了深色，App 就跟着深色。
/// 但有些人对某一种外观有明确偏好，还有人希望白天浅色、夜里深色，
/// 所以首次启动时问一次，之后也能在设置里改。
///
/// 四个取值是**互斥**的。这一点很关键：如果把"按时段自动切换"做成一个
/// 独立开关，就会出现"选了深色、又开着自动切换"这种自相矛盾的状态。
/// 做成同一个枚举的取值之后，这种冲突从结构上就不存在了。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case auto
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .auto: return "自动（按时间）"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var detail: String {
        switch self {
        case .system: return "系统切换深色时，App 一起变（推荐）"
        case .auto: return "白天浅色、夜间深色，到点自己换"
        case .light: return "始终使用白底界面"
        case .dark: return "始终使用深色界面"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .auto: return "clock.arrow.circlepath"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    // MARK: - 持久化

    static let storageKey = "guiwei.appearance"
    private static let chosenKey = "guiwei.appearanceChosen"

    static var current: AppAppearance {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return AppAppearance(rawValue: raw) ?? .system
    }

    /// 首次启动时是否已经问过外观偏好
    static var hasChosen: Bool {
        get { UserDefaults.standard.bool(forKey: chosenKey) }
        set { UserDefaults.standard.set(newValue, forKey: chosenKey) }
    }
}

/// 把「外观偏好」解析成「此刻应该用的配色方案」。
///
/// 关键设计：**存储的是偏好（可能是 auto），解析出来的是当下的方案**。
/// 千万不要把解析结果写回存储——那样一到晚上就会把用户的"自动"改写成"深色"，
/// 第二天早上就再也切不回浅色了。这是"不与其他功能冲突"的核心。
enum AppearanceSchedule {
    /// 白天时段：07:00 起、19:00 止。这两个值是固定的，不引入定位权限。
    static let dayStartHour = 7
    static let dayEndHour = 19

    /// 解析当下该用的配色方案。nil 表示交给系统。
    static func scheme(for appearance: AppAppearance, at date: Date = .now) -> ColorScheme? {
        switch appearance {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        case .auto:
            return isDaytime(at: date) ? .light : .dark
        }
    }

    static func isDaytime(at date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= dayStartHour && hour < dayEndHour
    }

    /// 距离下一次切换还有多少秒，用来安排定时刷新
    static func secondsUntilNextSwitch(from date: Date = .now) -> TimeInterval {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let nextHour = hour < dayStartHour ? dayStartHour : (hour < dayEndHour ? dayEndHour : dayStartHour)
        var components = DateComponents()
        components.hour = nextHour
        components.minute = 0
        components.second = 0
        guard let next = calendar.nextDate(after: date,
                                           matching: components,
                                           matchingPolicy: .nextTime) else {
            return 3600
        }
        return max(next.timeIntervalSince(date), 1)
    }
}
