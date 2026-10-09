import Foundation
import SwiftData

/// 数据的初始化与形态切换。
///
/// 分两层：
/// - **分类**属于 App 自身的分类体系，演示版和实用版都需要，永远补齐；
/// - **物品、位置、借出记录**只在演示版预置，而且只装载一次
///   （用 `AppDataMode.hasLoadedDemoData` 记住），避免使用者删空后又自动长回来。
enum DemoDataSeeder {
    /// App 启动时调用
    static func seedIfNeeded(context: ModelContext) {
        seedCategoriesIfNeeded(context: context)

        guard AppDataMode.current == .demo else { return }
        guard !AppDataMode.hasLoadedDemoData else { return }

        seedDemoContent(context: context)
        AppDataMode.hasLoadedDemoData = true
        try? context.save()
    }

    /// 设置页：切换到演示版时调用
    static func loadDemoContent(context: ModelContext) {
        seedCategoriesIfNeeded(context: context)
        seedDemoContent(context: context)
        AppDataMode.hasLoadedDemoData = true
        AppDataMode.set(.demo)
        try? context.save()
    }

    /// 设置页：切换到实用版时调用。物品、位置、借出记录全部清掉，
    /// 分类保留（它是 App 的分类体系，不是示例内容）。
    static func clearAllContent(context: ModelContext) {
        // 先删借出记录，再删物品，最后删位置，避免留下悬空引用
        for loan in (try? context.fetch(FetchDescriptor<LoanRecord>())) ?? [] {
            context.delete(loan)
        }
        for item in (try? context.fetch(FetchDescriptor<Item>())) ?? [] {
            context.delete(item)
        }
        // 位置是自引用树，先把父子关系解开再删，行为更可预测
        let spots = (try? context.fetch(FetchDescriptor<StorageSpot>())) ?? []
        for spot in spots { spot.parent = nil }
        for spot in spots { context.delete(spot) }

        AppDataMode.hasLoadedDemoData = false
        AppDataMode.set(.practical)
        try? context.save()
    }

    // MARK: - 分类

    private static func seedCategoriesIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ItemCategory>())) ?? []
        guard existing.isEmpty else { return }
        ItemCategory.defaults.forEach { context.insert($0) }
        try? context.save()
    }

    // MARK: - 演示内容（物品 + 位置 + 借出）

    private static func seedDemoContent(context: ModelContext) {
        // 已经东西就不重复塞
        let existingItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        guard existingItems.isEmpty else { return }

        let categories = (try? context.fetch(FetchDescriptor<ItemCategory>())) ?? []
        func category(_ name: String) -> ItemCategory? {
            categories.first { $0.name == name }
        }

        // 1. 位置：房间 → 容器 → 格位
        let bedroom = StorageSpot(name: "卧室", kind: .room, colorHex: "2E5FA3")
        let wardrobe = StorageSpot(name: "衣柜", kind: .container, colorHex: "2E5FA3", parent: bedroom)
        let drawer2 = StorageSpot(name: "第二层抽屉", kind: .slot, colorHex: "6B7280", parent: wardrobe)

        let study = StorageSpot(name: "书房", kind: .room, colorHex: "4B5BD2")
        let desk = StorageSpot(name: "书桌", kind: .container, colorHex: "4B5BD2", parent: study)
        let leftDrawer = StorageSpot(name: "左上抽屉", kind: .slot, colorHex: "6B7280", parent: desk)

        let kitchen = StorageSpot(name: "厨房", kind: .room, colorHex: "E08A2E")
        let fridge = StorageSpot(name: "冰箱", kind: .container, colorHex: "2E8FA3", parent: kitchen)
        let coldShelf = StorageSpot(name: "冷藏层", kind: .slot, colorHex: "2E8FA3", parent: fridge)

        let balcony = StorageSpot(name: "阳台", kind: .room, colorHex: "6B7280")
        let toolbox = StorageSpot(name: "工具箱", kind: .container, colorHex: "6B7280", parent: balcony)

        [bedroom, wardrobe, drawer2, study, desk, leftDrawer,
         kitchen, fridge, coldShelf, balcony, toolbox].forEach { context.insert($0) }

        // 2. 物品。时间都相对"今天"算，所以任何时候打开都能看到过期/临期/正常三种状态
        let cal = Calendar.current
        func day(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: .now) ?? .now
        }

        let items: [Item] = [
            make("全脂牛奶", qty: 2, category: category("食品"), spot: coldShelf,
                 expire: day(3), tags: ["冷藏"], note: "开封后三天内喝完"),
            make("希腊酸奶", qty: 4, category: category("食品"), spot: coldShelf, expire: day(-2)),
            make("维生素 C 泡腾片", qty: 1, category: category("药品"), spot: leftDrawer,
                 expire: day(180), tags: ["每日一片"]),
            make("布洛芬缓释胶囊", qty: 1, category: category("药品"), spot: leftDrawer,
                 expire: day(21), tags: ["常备药"]),
            make("护手霜", qty: 2, category: category("个护"), spot: drawer2, expire: day(400)),
            make("洗面奶", qty: 1, category: category("个护"), spot: drawer2, expire: day(9)),
            make("65W 氮化镓充电器", qty: 1, category: category("数码"), spot: desk,
                 expire: day(540), tags: ["出差必带"]),
            make("USB-C 数据线", qty: 3, category: category("数码"), spot: leftDrawer),
            make("螺丝刀套装", qty: 1, category: category("工具"), spot: toolbox, expire: day(900)),
            make("护照", qty: 1, category: category("证件"), spot: drawer2,
                 expire: day(1200), tags: ["重要", "随身"]),
            make("冲锋衣", qty: 1, category: category("衣物"), spot: wardrobe, tags: ["换季"]),
            make("滤芯备用装", qty: 2, category: category("其他"), spot: toolbox, expire: day(1))
        ]
        items.forEach { context.insert($0) }

        // 3. 收藏两件，方便演示「收藏」筛选
        items.first { $0.name == "螺丝刀套装" }?.isFavorite = true
        items.first { $0.name == "65W 氮化镓充电器" }?.isFavorite = true

        // 4. 借出记录：一条正常、一条逾期，演示"东西还会在别人手里"
        if let drill = items.first(where: { $0.name == "螺丝刀套装" }) {
            context.insert(LoanRecord(borrower: "室友 小林",
                                      lentAt: day(-5),
                                      dueAt: day(2),
                                      note: "装书架用，用完还我",
                                      item: drill))
        }
        if let charger = items.first(where: { $0.name == "65W 氮化镓充电器" }) {
            context.insert(LoanRecord(borrower: "隔壁 阿哲",
                                      lentAt: day(-12),
                                      dueAt: day(-3),
                                      note: "出差借走，已经逾期",
                                      item: charger))
        }
    }

    private static func make(_ name: String,
                             qty: Int,
                             category: ItemCategory?,
                             spot: StorageSpot?,
                             expire: Date? = nil,
                             tags: [String] = [],
                             note: String? = nil) -> Item {
        let item = Item(name: name, quantity: qty, note: note,
                        expireDate: expire, category: category, spot: spot)
        item.tags = tags
        item.isFavorite = tags.contains("重要")
        return item
    }
}
