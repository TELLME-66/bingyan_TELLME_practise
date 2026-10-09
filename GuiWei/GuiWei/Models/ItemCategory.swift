import Foundation
import SwiftData

/// 物品分类。先用独立模型而不是字符串，
/// 这样分类可以有图标、颜色和排序，方便做统计图。
@Model
final class ItemCategory {
    var name: String = ""
    var symbolName: String = "square.grid.2x2"
    var colorHex: String = "2E5FA3"
    var sortIndex: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    var items: [Item] = []

    init(name: String, symbolName: String = "square.grid.2x2",
         colorHex: String = "2E5FA3", sortIndex: Int = 0) {
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

extension ItemCategory {
    var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }

    /// 内置的默认分类，首次启动时写入
    static var defaults: [ItemCategory] {
        [
            ItemCategory(name: "食品", symbolName: "fork.knife", colorHex: "E08A2E", sortIndex: 0),
            ItemCategory(name: "药品", symbolName: "pills", colorHex: "D2564B", sortIndex: 1),
            ItemCategory(name: "个护", symbolName: "drop", colorHex: "2E8FA3", sortIndex: 2),
            ItemCategory(name: "数码", symbolName: "cable.connector", colorHex: "4B5BD2", sortIndex: 3),
            ItemCategory(name: "工具", symbolName: "wrench.and.screwdriver", colorHex: "6B7280", sortIndex: 4),
            ItemCategory(name: "证件", symbolName: "doc.text", colorHex: "8A5BD2", sortIndex: 5),
            ItemCategory(name: "衣物", symbolName: "tshirt", colorHex: "3FA36B", sortIndex: 6),
            ItemCategory(name: "其他", symbolName: "shippingbox", colorHex: "9AA1AC", sortIndex: 7)
        ]
    }
}
