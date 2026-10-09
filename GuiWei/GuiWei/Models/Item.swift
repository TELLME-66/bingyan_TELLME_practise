import Foundation
import SwiftData

// MARK: - 到期状态

enum ExpiryState: String {
    case none
    case safe
    case soon
    case expired

    var label: String {
        switch self {
        case .none: return "无期限"
        case .safe: return "正常"
        case .soon: return "临期"
        case .expired: return "已过期"
        }
    }
}

// MARK: - 物品

@Model
final class Item {
    /// 稳定标识：深链（guiwei://item/<uid>）、Spotlight 索引、通知标识都用它。
    /// 不用 SwiftData 的 persistentModelID，是因为那个值不适合直接写进 URL。
    var uid: String = UUID().uuidString
    var name: String = ""
    var quantity: Int = 1
    var note: String?
    var expireDate: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isFavorite: Bool = false
    var tags: [String] = []

    /// 原图存到数据库外部文件，避免把 .store 撑大
    @Attribute(.externalStorage) var imageData: Data?
    /// 列表用的缩略图，体积小，直接内联存储，滚动时不必解码大图
    var thumbnailData: Data?

    var category: ItemCategory?
    var spot: StorageSpot?

    @Relationship(deleteRule: .cascade, inverse: \LoanRecord.item)
    var loans: [LoanRecord] = []

    init(name: String,
         quantity: Int = 1,
         note: String? = nil,
         expireDate: Date? = nil,
         category: ItemCategory? = nil,
         spot: StorageSpot? = nil,
         imageData: Data? = nil) {
        self.name = name
        self.quantity = quantity
        self.note = note
        self.expireDate = expireDate
        self.category = category
        self.spot = spot
        self.imageData = imageData
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension Item {
    /// 当前仍在借出中的记录（同一时刻最多一条）
    var activeLoan: LoanRecord? {
        loans.filter { $0.returnedAt == nil }.sorted { $0.lentAt > $1.lentAt }.first
    }

    var isLentOut: Bool { activeLoan != nil }

    var daysUntilExpiry: Int? {
        guard let expireDate else { return nil }
        let cal = Calendar.current
        let from = cal.startOfDay(for: .now)
        let to = cal.startOfDay(for: expireDate)
        return cal.dateComponents([.day], from: from, to: to).day
    }

    var expiryState: ExpiryState {
        guard let days = daysUntilExpiry else { return .none }
        if days < 0 { return .expired }
        if days <= 30 { return .soon }
        return .safe
    }

    /// 一句人话描述剩余时间，列表和详情共用
    var expiryText: String? {
        guard let days = daysUntilExpiry else { return nil }
        if days < 0 { return "已过期 \(-days) 天" }
        if days == 0 { return "今天到期" }
        return "还剩 \(days) 天"
    }

    var locationPath: String { spot?.fullPath ?? "未归位" }

    func touch() { updatedAt = .now }
}
