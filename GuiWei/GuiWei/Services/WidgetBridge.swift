import Foundation
import SwiftData

// MARK: - 小组件快照

/// 主 App 与小组件之间传递的数据快照。
///
/// 为什么用"快照"而不是让小组件直接读 SwiftData：
/// 小组件运行在独立进程里，要读到主 App 的数据库必须先配置 App Group，
/// 而且 SwiftData 在小组件进程里初始化的开销不小、时间线刷新也容易踩坑。
/// 更稳的做法是主 App 在数据变化时写一份很小的 JSON 到共享 UserDefaults，
/// 小组件只读这份 JSON。数据量小、没有并发问题、时间线刷新也快。
struct WidgetSnapshot: Codable {
    struct Line: Codable, Identifiable {
        var id: String
        var name: String
        var place: String
        var days: Int?
    }

    var totalKinds: Int
    var totalQuantity: Int
    var expiringCount: Int
    var expiredCount: Int
    var lentCount: Int
    var lines: [Line]
    var updatedAt: Date

    static let empty = WidgetSnapshot(totalKinds: 0, totalQuantity: 0,
                                      expiringCount: 0, expiredCount: 0,
                                      lentCount: 0, lines: [], updatedAt: .now)
}

/// 共享容器的读写。App Group 没配置时自动退回标准 UserDefaults，
/// 这样主 App 在没有开发者账号的环境下也能正常运行，只是小组件读不到数据。
enum WidgetStore {
    static let appGroupID = "group.com.bingyan.guiwei"
    static let snapshotKey = "guiwei.widget.snapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

// MARK: - 发布快照

/// 把当前数据汇总成一份小组件快照并写入共享容器。
/// 所有会改动数据的地方（启动、增删改、重置）都应该调一次。
enum WidgetBridge {
    static func publish(items: [Item]) {
        let expiring = items.filter { $0.expiryState == .soon }
        let expired = items.filter { $0.expiryState == .expired }
        let lent = items.filter(\.isLentOut)

        // 小组件只展示最紧急的 3 条，避免快照变大
        let urgent = items
            .filter { $0.expiryState == .soon || $0.expiryState == .expired }
            .sorted { ($0.daysUntilExpiry ?? .max) < ($1.daysUntilExpiry ?? .max) }
            .prefix(3)
            .map { item in
                WidgetSnapshot.Line(id: item.uid,
                                    name: item.name,
                                    place: item.locationPath,
                                    days: item.daysUntilExpiry)
            }

        let snapshot = WidgetSnapshot(totalKinds: items.count,
                                      totalQuantity: items.reduce(0) { $0 + $1.quantity },
                                      expiringCount: expiring.count,
                                      expiredCount: expired.count,
                                      lentCount: lent.count,
                                      lines: Array(urgent),
                                      updatedAt: .now)
        WidgetStore.save(snapshot)
    }
}
