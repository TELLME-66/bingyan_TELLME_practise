import ActivityKit
import Foundation

/// 与 App 侧 `GuiWei/LiveActivity/GuiWeiActivityAttributes.swift` 保持一致。
/// 两个 target 各持一份，字段与类型名必须完全相同。
struct GuiWeiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var dueDate: Date?
        var isReturned: Bool

        var daysLeft: Int? {
            guard let dueDate else { return nil }
            let cal = Calendar.current
            return cal.dateComponents([.day],
                                      from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: dueDate)).day
        }

        /// 灵动岛紧凑区域很窄，只放得下几个字
        var shortText: String {
            if isReturned { return "已还" }
            guard let days = daysLeft else { return "借出" }
            if days < 0 { return "逾期" }
            if days == 0 { return "今天" }
            return "\(days)天"
        }

        var statusText: String {
            if isReturned { return "已归还" }
            guard let days = daysLeft else { return "借出中" }
            if days < 0 { return "已逾期 \(-days) 天" }
            if days == 0 { return "今天到期" }
            return "还剩 \(days) 天归还"
        }
    }

    var itemName: String
    var borrower: String
    var locationPath: String
}
