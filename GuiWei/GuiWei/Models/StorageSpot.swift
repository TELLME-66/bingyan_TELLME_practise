import Foundation
import SwiftData

// MARK: - 存放位置

/// 位置分三层：房间 → 容器 → 格位。
/// 用 parent/children 自引用表达层级，而不是三个写死的字段，
/// 这样以后想加"第几层抽屉"也不用改模型。
enum SpotKind: String, CaseIterable, Identifiable {
    case room
    case container
    case slot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .room: return "房间"
        case .container: return "容器"
        case .slot: return "格位"
        }
    }

    var symbolName: String {
        switch self {
        case .room: return "house"
        case .container: return "shippingbox"
        case .slot: return "tray"
        }
    }
}

@Model
final class StorageSpot {
    var name: String = ""
    var kindRaw: String = SpotKind.container.rawValue
    var note: String?
    var colorHex: String = "2E5FA3"
    var createdAt: Date = Date.now
    var parent: StorageSpot?

    @Relationship(deleteRule: .nullify, inverse: \StorageSpot.parent)
    var children: [StorageSpot] = []

    @Relationship(deleteRule: .nullify, inverse: \Item.spot)
    var items: [Item] = []

    init(name: String, kind: SpotKind = .container, note: String? = nil,
         colorHex: String = "2E5FA3", parent: StorageSpot? = nil) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.note = note
        self.colorHex = colorHex
        self.parent = parent
        self.createdAt = .now
    }
}

extension StorageSpot {
    var kind: SpotKind { SpotKind(rawValue: kindRaw) ?? .container }

    /// 从最顶层一路拼到当前节点，例如「卧室 › 衣柜 › 第二层抽屉」
    var fullPath: String {
        var parts: [String] = [name]
        var node = parent
        var guardCount = 0
        while let current = node, guardCount < 8 {
            parts.insert(current.name, at: 0)
            node = current.parent
            guardCount += 1
        }
        return parts.joined(separator: " › ")
    }

    /// 只算直接放在这里的物品；容器层级靠 children 递归汇总
    var directItemCount: Int { items.count }

    var totalItemCount: Int { totalItemCount(depth: 0) }

    /// 递归汇总。带深度上限：正常操作不会成环（编辑页已排除把自己或后代设为上级），
    /// 但万一数据被外部导入成环，这里也不会死循环。
    private func totalItemCount(depth: Int) -> Int {
        guard depth < 8 else { return items.count }
        return items.count + children.reduce(0) { $0 + $1.totalItemCount(depth: depth + 1) }
    }

    var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity } + children.reduce(0) { $0 + $1.totalQuantity }
    }
}
