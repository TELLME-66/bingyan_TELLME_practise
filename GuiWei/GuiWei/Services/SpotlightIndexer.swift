import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// 把物品索引进系统 Spotlight，在桌面下拉搜索里直接搜到「归位」里的东西。
/// 这是接入苹果生态里成本最低、感知最强的一步。
enum SpotlightIndexer {
    static let domainIdentifier = "com.bingyan.guiwei.items"

    /// 全量重建索引。物品量在几百条这个量级，整体重建最简单也最不容易出错。
    static func reindex(items: [Item]) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            let searchable = items.map(makeSearchableItem)
            guard !searchable.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(searchable, completionHandler: nil)
        }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier],
                                                          completionHandler: nil)
    }

    private static func makeSearchableItem(for item: Item) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = item.name
        attributes.contentDescription = description(for: item)
        attributes.keywords = keywords(for: item)
        if let thumbnail = item.thumbnailData {
            attributes.thumbnailData = thumbnail
        }
        return CSSearchableItem(uniqueIdentifier: item.uid,
                                domainIdentifier: domainIdentifier,
                                attributeSet: attributes)
    }

    private static func description(for item: Item) -> String {
        var parts: [String] = [item.locationPath]
        if let category = item.category { parts.append(category.name) }
        if item.isLentOut, let loan = item.activeLoan { parts.append("借给 \(loan.borrower)") }
        if let expiry = item.expiryText { parts.append(expiry) }
        return parts.joined(separator: " · ")
    }

    private static func keywords(for item: Item) -> [String] {
        var words = ["归位", "物品", item.name, item.locationPath]
        words.append(contentsOf: item.tags)
        if let category = item.category { words.append(category.name) }
        if let spot = item.spot { words.append(spot.name) }
        return words
    }
}
