import ActivityKit
import Foundation

/// 借出追踪的实时活动数据。
///
/// 说明：App 与小组件扩展是两个独立的 target，这个定义在两边各有一份
/// （`GuiWei/LiveActivity/` 与 `GuiWeiWidgetExtension/`），内容必须保持一致。
/// 正式项目里应该把它抽成一个共享的 Swift Package，两个 target 同时依赖。
/// ActivityKit 按类型名匹配活动，因此两侧同名同结构即可正常工作。
struct GuiWeiActivityAttributes: ActivityAttributes {
    /// 会随时间变化的部分
    struct ContentState: Codable, Hashable {
        /// 应还日期，没有约定则为空
        var dueDate: Date?
        /// 是否已经归还
        var isReturned: Bool

        /// 距离应还还有几天（按自然日算）
        var daysLeft: Int? {
            guard let dueDate else { return nil }
            let cal = Calendar.current
            return cal.dateComponents([.day],
                                      from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: dueDate)).day
        }

        /// 灵动岛紧凑区域只放得下几个字，这里统一成短文案
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

    /// 整个活动期间不变的部分
    var itemName: String
    var borrower: String
    /// 物品原本放在哪——归还后要放回去的地方
    var locationPath: String
}
