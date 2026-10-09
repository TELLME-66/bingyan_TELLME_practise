import Foundation

/// 与 App 侧 `Services/WidgetBridge.swift` 中的定义保持一致。
/// 小组件运行在独立进程，直接读数据库需要 App Group；这里改为读
/// App 写进共享 UserDefaults 的一份小 JSON 快照，更轻也更稳。
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

    static let preview = WidgetSnapshot(
        totalKinds: 12, totalQuantity: 20,
        expiringCount: 4, expiredCount: 1, lentCount: 2,
        lines: [
            Line(id: "1", name: "滤芯备用装", place: "阳台 › 工具箱", days: 1),
            Line(id: "2", name: "全脂牛奶", place: "厨房 › 冰箱 › 冷藏层", days: 3),
            Line(id: "3", name: "洗面奶", place: "卧室 › 衣柜 › 第二层抽屉", days: 9)
        ],
        updatedAt: .now)
}

enum WidgetStore {
    static let appGroupID = "group.com.bingyan.guiwei"
    static let snapshotKey = "guiwei.widget.snapshot"

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
