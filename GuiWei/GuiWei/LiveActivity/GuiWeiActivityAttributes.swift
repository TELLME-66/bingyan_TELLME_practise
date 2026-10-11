import ActivityKit
import Foundation

/// 实时活动的数据。
///
/// 只表达**一件事**：现在最该处理的那件东西。
/// 优先顺序固定为 **到期 > 归还**——只要还有东西要到期，就不显示归还。
///
/// 说明：App 与小组件扩展是两个独立的 target，这个定义在两边各有一份，
/// 内容必须保持完全一致。正式项目里应该抽成共享的 Swift Package。
struct GuiWeiActivityAttributes: ActivityAttributes {

    /// 这件事属于哪一类。到期优先于归还。
    enum Kind: String, Codable, Hashable {
        case expiry   // 快到期了
        case loan     // 该要回来了
    }

    /// 会随时间变化的部分
    struct ContentState: Codable, Hashable {
        /// 那件事的日期：到期日 / 应还日
        var dueDate: Date?
        /// 同类的事一共有几件（用于显示「另有 N 件」）
        var pendingCount: Int

        /// 距离那个日期还有几天（自然日）
        var daysLeft: Int? {
            guard let dueDate else { return nil }
            let cal = Calendar.current
            return cal.dateComponents([.day],
                                      from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: dueDate)).day
        }

        /// 灵动岛紧凑区很窄，只能放几个字。
        /// 全部控制在 3 个汉字以内，iPhone 17 Pro 与 18 Pro 都不会被裁切。
        var shortText: String {
            guard let days = daysLeft else { return "关注" }
            if days < 0 { return "逾期" }
            if days == 0 { return "今天" }
            if days > 99 { return "99+" }
            return "\(days)天"
        }

        /// 展开态与锁定屏用的完整描述
        var statusText: String {
            guard let days = daysLeft else { return "待处理" }
            if days < 0 { return "已逾期 \(-days) 天" }
            if days == 0 { return "就是今天" }
            return "还剩 \(days) 天"
        }

        /// 进度条：越接近期限越满。
        /// 起点是 30 天前，30 天及更远时为 0。
        var progress: Double {
            guard let days = daysLeft else { return 0 }
            if days <= 0 { return 1 }
            return min(max(1 - Double(days) / 30.0, 0), 1)
        }
    }

    var kind: Kind
    /// 物品名
    var title: String
    /// 到期 → 存放位置；归还 → 借给谁
    var subtitle: String
    /// 归还后该放回哪里（到期场景留空）
    var locationPath: String

    var symbolName: String {
        kind == .expiry ? "clock.badge.exclamationmark" : "person.fill"
    }

    var accentName: String {
        kind == .expiry ? "expiry" : "loan"
    }
}
