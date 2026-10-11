import AppIntents
import Foundation
import SwiftData
import SwiftUI

// MARK: - 共用的查询辅助

/// Siri 与快捷指令共用的数据存取逻辑。
@MainActor
private enum IntentStore {
    static func context() -> ModelContext { ModelContext(AppContainer.shared) }

    static func allItems(_ context: ModelContext) -> [Item] {
        (try? context.fetch(FetchDescriptor<Item>())) ?? []
    }

    static func allSpots(_ context: ModelContext) -> [StorageSpot] {
        (try? context.fetch(FetchDescriptor<StorageSpot>())) ?? []
    }

    /// 按名字模糊匹配一件物品；命中多件时返回第一件
    static func match(_ keyword: String, in context: ModelContext) -> Item? {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let items = allItems(context)
        // 先精确、再包含、最后按标签与位置匹配
        return items.first { $0.name == key }
            ?? items.first { $0.name.localizedStandardContains(key) }
            ?? items.first { $0.tags.contains { $0.localizedStandardContains(key) } }
            ?? items.first { $0.locationPath.localizedStandardContains(key) }
    }

    /// 找位置；找不到就当场建一个，避免用户还要先去 App 里创建
    static func findOrCreateSpot(named raw: String, in context: ModelContext) -> StorageSpot? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        // 支持「卧室 衣柜」这种用空格表达层级的说法
        let parts = name.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var parent: StorageSpot? = nil
        var current: StorageSpot? = nil
        for (index, part) in parts.enumerated() {
            let siblings = allSpots(context).filter { $0.parent?.persistentModelID == parent?.persistentModelID }
            if let hit = siblings.first(where: { $0.name == part }) {
                current = hit
            } else {
                let kind: SpotKind = index == 0 ? .room : (index == parts.count - 1 ? .slot : .container)
                let spot = StorageSpot(name: part, kind: kind, parent: parent)
                context.insert(spot)
                current = spot
            }
            parent = current
        }
        return current
    }

    static func findCategory(named raw: String, in context: ModelContext) -> ItemCategory? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<ItemCategory>())) ?? []
        return all.first { $0.name == name }
    }
}


// MARK: - 物品实体

/// 让 Siri 能把口语里的「护照」解析成一件具体物品。
///
/// 这是 **App Shortcuts 短语能嵌入参数的唯一方式**：
/// 短语里的参数必须是 `AppEntity` 或 `AppEnum`，不能用普通 String，
/// 而且一条短语只能带一个参数。所以「找东西」做成一句话，
/// 「换位置 / 借出去」由 Siri 追问剩下那一个值。
struct ItemEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "物品"
    static var defaultQuery = ItemEntityQuery()

    var id: String
    var name: String
    var locationPath: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(locationPath)")
    }
}

struct ItemEntityQuery: EntityStringQuery {

    private func snapshot() -> [ItemEntity] {
        let context = ModelContext(AppContainer.shared)
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        return items.map {
            ItemEntity(id: $0.uid, name: $0.name, locationPath: $0.locationPath)
        }
    }

    func entities(for identifiers: [String]) async throws -> [ItemEntity] {
        snapshot().filter { identifiers.contains($0.id) }
    }

    /// Siri 会把手里的说法整句传进来，这里做模糊匹配
    func entities(matching string: String) async throws -> [ItemEntity] {
        let key = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let context = ModelContext(AppContainer.shared)
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        return items.filter { item in
            item.name.localizedStandardContains(key)
                || item.tags.contains { $0.localizedStandardContains(key) }
                || item.locationPath.localizedStandardContains(key)
        }.map { ItemEntity(id: $0.uid, name: $0.name, locationPath: $0.locationPath) }
    }

    /// 打开 App 时给出的候选：最近更新的 20 件
    func suggestedEntities() async throws -> [ItemEntity] {
        let context = ModelContext(AppContainer.shared)
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        return items.sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map { ItemEntity(id: $0.uid, name: $0.name, locationPath: $0.locationPath) }
    }
}

// MARK: - 找东西

/// 本 App 最核心的一句话：「我的护照放哪了」。
///
/// 短语里嵌了 `\(\.$item)`，所以 Siri 能直接从句子里把物品名抽出来，
/// **不会再追问一次**——这是它好不好用的关键。
struct FindItemWhereIntent: AppIntent {
    static var title: LocalizedStringResource = "东西放哪了"
    static var description = IntentDescription("问「归位」某件东西放在哪里。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "物品名称", requestValueDialog: "你要找什么？")
    var item: ItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("问「归位」\(\.$item) 放在哪")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = IntentStore.context()
        let items = IntentStore.allItems(context)
        // Siri 已经把口语解析成了具体物品，这里按 uid 取回最新状态
        let matches = items.filter { $0.uid == item.id }

        switch matches.count {
        case 0:
            return .result(
                dialog: "这件东西好像已经被删掉了。",
                view: SiriAnswerCard(symbol: "questionmark.circle",
                                     tint: .secondary,
                                     title: "找不到这件物品",
                                     lines: []))
        case 1:
            let item = matches[0]
            var lines: [String] = []
            var dialog = ""
            if item.isLentOut, let loan = item.activeLoan {
                dialog = "「\(item.name)」借给了\(loan.borrower)。"
                lines.append("借给了 \(loan.borrower)")
                if let due = loan.dueAt {
                    lines.append("约定归还 \(due.formatted(date: .abbreviated, time: .omitted))")
                }
            } else {
                dialog = "「\(item.name)」在\(item.locationPath)。"
                lines.append(item.locationPath)
            }
            if let expiry = item.expiryText {
                dialog += expiry + "。"
                lines.append(expiry)
            }
            return .result(
                dialog: IntentDialog(stringLiteral: dialog),
                view: SiriAnswerCard(symbol: item.isLentOut ? "person.fill" : "mappin.and.ellipse",
                                     tint: item.isLentOut ? .orange : Color(hex: "2E5FA3"),
                                     title: item.name,
                                     lines: lines))
        default:
            let top = matches.prefix(3).map { "\($0.name)（\($0.locationPath)）" }
            let extra = matches.count > 3 ? " 等 \(matches.count) 件" : ""
            return .result(
                dialog: IntentDialog(stringLiteral: "找到 \(matches.count) 件：\(top.joined(separator: "、"))\(extra)。"),
                view: SiriAnswerCard(symbol: "square.stack.3d.up",
                                     tint: Color(hex: "2E5FA3"),
                                     title: "找到 \(matches.count) 件",
                                     lines: matches.prefix(3).map { "\($0.name) · \($0.locationPath)" }))
        }
    }
}

// MARK: - 记一件物品

/// 「用归位记一下充电宝」——**位置是可选的**。
///
/// 之前位置是必填，用户说一句 Siri 还要追问一句，这是「不好用」的最大来源。
/// 改成可选之后，一句话就能记完；想指定位置也支持「记一下充电宝放在书房」。
struct AddItemIntent: AppIntent {
    static var title: LocalizedStringResource = "记一件物品"
    static var description = IntentDescription("把一件物品记到「归位」。位置可以一起说，也可以之后补。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "物品名称", requestValueDialog: "要记下什么东西？")
    var name: String

    @Parameter(title: "存放位置", requestValueDialog: "它放在哪里？")
    var spotName: String?

    @Parameter(title: "分类")
    var categoryName: String?

    @Parameter(title: "到期日期")
    var expireDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$name) 记到「归位」") {
            \.$spotName
            \.$categoryName
            \.$expireDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = IntentStore.context()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            return .result(dialog: "要记下什么东西？")
        }

        let spot = spotName.flatMap { IntentStore.findOrCreateSpot(named: $0, in: context) }
        let category = categoryName.flatMap { IntentStore.findCategory(named: $0, in: context) }

        let item = Item(name: cleanName, category: category, spot: spot)
        item.expireDate = expireDate
        context.insert(item)
        try? context.save()

        await NotificationService.shared.scheduleExpiry(for: item)
        WidgetBridge.publish(items: IntentStore.allItems(context))

        var lines: [String] = []
        let dialog: String
        if let spot {
            lines.append(spot.fullPath)
            dialog = "记下了，「\(cleanName)」放在\(spot.fullPath)。"
        } else {
            lines.append("还没归位")
            dialog = "记下「\(cleanName)」了。要不要顺手说一句它放哪？"
        }
        if let expireDate {
            lines.append("到期 \(expireDate.formatted(date: .abbreviated, time: .omitted))")
        }

        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: SiriAnswerCard(symbol: "checkmark.circle.fill",
                                 tint: Color(hex: "3FA36B"),
                                 title: "已记下「\(cleanName)」",
                                 lines: lines))
    }
}

// MARK: - 我把 X 放到 Y 了

/// 收纳完顺手一句话，把物品挪到新位置。位置不存在会自动建。
struct MoveItemIntent: AppIntent {
    static var title: LocalizedStringResource = "把东西放到某处"
    static var description = IntentDescription("告诉「归位」某件东西换到哪了，位置不存在会自动创建。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "物品名称", requestValueDialog: "哪件东西？")
    var item: ItemEntity

    @Parameter(title: "新位置", requestValueDialog: "放到哪里了？")
    var spotName: String

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$item) 放到 \(\.$spotName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = IntentStore.context()

        guard let target = IntentStore.allItems(context).first(where: { $0.uid == item.id }) else {
            return .result(
                dialog: "这件东西好像已经被删掉了。",
                view: SiriAnswerCard(symbol: "questionmark.circle", tint: .secondary,
                                     title: "找不到这件物品", lines: []))
        }

        guard let spot = IntentStore.findOrCreateSpot(named: spotName, in: context) else {
            return .result(dialog: "没听清放到哪里，再说一次位置？")
        }

        target.spot = spot
        target.touch()
        try? context.save()
        WidgetBridge.publish(items: IntentStore.allItems(context))

        return .result(
            dialog: "好，「\(target.name)」放到\(spot.fullPath)了。",
            view: SiriAnswerCard(symbol: "mappin.and.ellipse", tint: Color(hex: "2E5FA3"),
                                 title: target.name, lines: [spot.fullPath]))
    }
}

// MARK: - 借出去了

/// 「充电器借给阿哲了」——一句话登记借出。
struct LendItemIntent: AppIntent {
    static var title: LocalizedStringResource = "借给别人"
    static var description = IntentDescription("记录某件东西借给了谁，应还日期可以之后在 App 里补。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "物品", requestValueDialog: "借出去的是哪件？")
    var item: ItemEntity

    @Parameter(title: "借给谁", requestValueDialog: "借给谁了？")
    var borrower: String

    @Parameter(title: "几天后归还")
    var daysUntilDue: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$item) 借给 \(\.$borrower)") {
            \.$daysUntilDue
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = IntentStore.context()

        guard let target = IntentStore.allItems(context).first(where: { $0.uid == item.id }) else {
            return .result(
                dialog: "这件东西好像已经被删掉了。",
                view: SiriAnswerCard(symbol: "questionmark.circle", tint: .secondary,
                                     title: "找不到这件物品", lines: []))
        }

        let who = borrower.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { return .result(dialog: "借给谁了？") }

        // 已经有未归还的记录，先结掉再新建，避免同一件东西两条借出
        if let open = target.activeLoan {
            open.returnedAt = .now
        }
        let due = daysUntilDue.map { Date.now.addingTimeInterval(Double($0) * 86400) }
        let loan = LoanRecord(borrower: who, dueAt: due, item: target)
        context.insert(loan)
        target.touch()
        try? context.save()

        if due != nil { await NotificationService.shared.scheduleLoanDue(for: loan) }

        var lines = ["借给 \(who)"]
        if let due { lines.append("应还 \(due.formatted(date: .abbreviated, time: .omitted))") }

        return .result(
            dialog: "记下了，「\(target.name)」借给了\(who)。",
            view: SiriAnswerCard(symbol: "person.fill", tint: .orange,
                                 title: target.name, lines: lines))
    }
}

// MARK: - 快过期了什么

/// 「有什么快过期了」——临期清单一句话问出来。
struct ExpiringItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "有什么快过期了"
    static var description = IntentDescription("列出临期和已过期的物品，以及借在外面没还的。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = IntentStore.context()
        let items = IntentStore.allItems(context)

        let expiring = items
            .filter { $0.expiryState == .soon || $0.expiryState == .expired }
            .sorted { ($0.daysUntilExpiry ?? .max) < ($1.daysUntilExpiry ?? .max) }
        let lent = items.filter(\.isLentOut)

        if expiring.isEmpty && lent.isEmpty {
            return .result(
                dialog: "暂时没有快过期的东西，也没有借在外面的。",
                view: SiriAnswerCard(symbol: "checkmark.seal.fill", tint: Color(hex: "3FA36B"),
                                     title: "一切正常", lines: ["没有临期，也没有外借"]))
        }

        var lines: [String] = expiring.prefix(4).map {
            "\($0.name) · \($0.expiryText ?? "")"
        }
        if !lent.isEmpty {
            lines.append("借出 \(lent.count) 件")
        }

        var dialog = ""
        if expiring.isEmpty {
            dialog = "没有快过期的。"
        } else {
            let head = expiring.prefix(3).map { "\($0.name)\($0.expiryText ?? "")" }
            dialog = "\(expiring.count) 件需要注意：\(head.joined(separator: "，"))。"
        }
        if !lent.isEmpty { dialog += "另外 \(lent.count) 件还借在外面。" }

        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: SiriAnswerCard(symbol: "clock.badge.exclamationmark", tint: .orange,
                                 title: "需要关注 \(expiring.count + lent.count) 件",
                                 lines: lines))
    }
}

// MARK: - 物品概况

struct StorageSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "问一句物品概况"
    static var description = IntentDescription("让「归位」汇报物品总数、临期数量和借出情况。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = IntentStore.context()
        let items = IntentStore.allItems(context)
        let spots = IntentStore.allSpots(context)
        let expiring = items.filter { $0.expiryState == .soon || $0.expiryState == .expired }
        let lent = items.filter(\.isLentOut)
        let totalQty = items.reduce(0) { $0 + $1.quantity }

        var parts: [String] = ["一共记了 \(items.count) 件物品，共 \(totalQty) 个"]
        parts.append(expiring.isEmpty ? "没有临期的" : "\(expiring.count) 件临期或过期")
        if !lent.isEmpty { parts.append("\(lent.count) 件借在外面") }

        return .result(
            dialog: IntentDialog(stringLiteral: parts.joined(separator: "，") + "。"),
            view: SiriAnswerCard(symbol: "shippingbox.fill", tint: Color(hex: "2E5FA3"),
                                 title: "\(items.count) 件物品",
                                 lines: [
                                    "共 \(totalQty) 个 · 分布在 \(spots.count) 个位置",
                                    expiring.isEmpty ? "没有临期" : "\(expiring.count) 件临期或过期",
                                    lent.isEmpty ? "没有外借" : "\(lent.count) 件借在外面",
                                 ]))
    }
}

// MARK: - Siri 回答卡片

/// Siri 回答时显示的小卡片。比纯文字更像「归位」自己的界面。
struct SiriAnswerCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 快捷短语

/// 这些短语会自动出现在 Siri 与「快捷指令」App 里，用户不用自己配置。
///
/// **两条设计原则**（也是这次改版的重点）：
/// 1. 短语里嵌 `\(\.$参数)`，让 Siri 直接从句子里抽值，不要再追问一轮；
/// 2. 每个 Intent 给多种说法，覆盖日常口语的不同讲法。
struct GuiWeiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // 找东西：最高频。短语里嵌了物品实体，Siri 能直接从句子里解析出是哪件东西，
        // **一句话直达，不再追问** —— 这是这次改版最关键的提升。
        AppShortcut(intent: FindItemWhereIntent(),
                    phrases: [
                        "\(.applicationName)\(\.$item)放哪了",
                        "\(.applicationName)我的\(\.$item)放哪了",
                        "\(.applicationName)\(\.$item)在哪",
                    ],
                    shortTitle: "东西放哪了",
                    systemImageName: "magnifyingglass")

        // 记东西：位置已改为可选，Siri 只需要问"记什么"这一个问题
        AppShortcut(intent: AddItemIntent(),
                    phrases: [
                        "用\(.applicationName)记一件东西",
                        "\(.applicationName)记一件东西",
                        "用\(.applicationName)记一下",
                    ],
                    shortTitle: "记一件物品",
                    systemImageName: "plus.square.on.square")

        // 换位置：短语带物品，Siri 只追问新位置
        AppShortcut(intent: MoveItemIntent(),
                    phrases: [
                        "\(.applicationName)把\(\.$item)换个位置",
                        "\(.applicationName)\(\.$item)换地方了",
                    ],
                    shortTitle: "换个位置",
                    systemImageName: "arrow.triangle.turn.up.right.circle")

        // 借出去：短语带物品，Siri 只追问借给谁
        AppShortcut(intent: LendItemIntent(),
                    phrases: [
                        "\(.applicationName)把\(\.$item)借出去",
                        "\(.applicationName)\(\.$item)借出去了",
                    ],
                    shortTitle: "借给别人",
                    systemImageName: "person.badge.plus")

        // 临期清单：无需追问
        AppShortcut(intent: ExpiringItemsIntent(),
                    phrases: [
                        "\(.applicationName)什么快过期了",
                        "\(.applicationName)有哪些快过期了",
                        "\(.applicationName)临期的东西",
                    ],
                    shortTitle: "快过期了什么",
                    systemImageName: "clock.badge.exclamationmark")

        // 概况：无需追问
        AppShortcut(intent: StorageSummaryIntent(),
                    phrases: [
                        "\(.applicationName)汇报一下物品情况",
                        "\(.applicationName)物品概况",
                    ],
                    shortTitle: "物品概况",
                    systemImageName: "chart.bar")
    }
}
