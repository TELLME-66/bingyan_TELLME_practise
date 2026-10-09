import AppIntents
import Foundation
import SwiftData

// MARK: - 记一件物品

/// 用 Siri 或快捷指令往「归位」里添加物品。
/// 位置如果不存在会自动创建，这样用户可以直接说"记一下充电宝放在书房"。
struct AddItemIntent: AppIntent {
    static var title: LocalizedStringResource = "记一件物品"
    static var description = IntentDescription("把一件物品记到「归位」，并指定它放在哪里。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "物品名称", requestValueDialog: "要记下什么东西？")
    var name: String

    @Parameter(title: "存放位置", requestValueDialog: "它放在哪里？")
    var spotName: String

    @Parameter(title: "分类")
    var categoryName: String?

    @Parameter(title: "到期日期")
    var expireDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$name) 放到 \(\.$spotName)") {
            \.$categoryName
            \.$expireDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppContainer.shared)

        let spot = findOrCreateSpot(named: spotName, in: context)
        let category = categoryName.flatMap { findCategory(named: $0, in: context) }

        let item = Item(name: name, category: category, spot: spot)
        item.expireDate = expireDate
        context.insert(item)
        try? context.save()

        await NotificationService.shared.scheduleExpiry(for: item)

        let location = spot?.fullPath ?? spotName
        return .result(dialog: "已经记下「\(name)」，放在\(location)。")
    }

    @MainActor
    private func findOrCreateSpot(named raw: String, in context: ModelContext) -> StorageSpot? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<StorageSpot>())) ?? []
        if let hit = all.first(where: { $0.name == name }) { return hit }
        let spot = StorageSpot(name: name, kind: .container)
        context.insert(spot)
        return spot
    }

    @MainActor
    private func findCategory(named raw: String, in context: ModelContext) -> ItemCategory? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<ItemCategory>())) ?? []
        return all.first { $0.name == name }
    }
}

// MARK: - 东西放哪了

/// 用 Siri 问「我的护照放哪了」。
/// 这是本 App 最核心的一句话，也是整个产品定位的体现。
struct FindItemWhereIntent: AppIntent {
    static var title: LocalizedStringResource = "东西放哪了"
    static var description = IntentDescription("问「归位」某件东西放在哪里。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "物品名称", requestValueDialog: "你要找什么？")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("问「归位」\(\.$query) 放在哪")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppContainer.shared)
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !keyword.isEmpty else {
            return .result(dialog: "告诉我物品的名字，我帮你找。")
        }

        let matches = all.filter { item in
            item.name.localizedStandardContains(keyword)
                || item.tags.contains { $0.localizedStandardContains(keyword) }
                || item.locationPath.localizedStandardContains(keyword)
        }

        switch matches.count {
        case 0:
            return .result(dialog: "没有找到和「\(keyword)」有关的物品。")
        case 1:
            let item = matches[0]
            var line = "「\(item.name)」在\(item.locationPath)。"
            if item.isLentOut, let loan = item.activeLoan {
                line += "不过它现在借给了\(loan.borrower)。"
            }
            if let expiry = item.expiryText {
                line += "\(expiry)。"
            }
            return .result(dialog: IntentDialog(stringLiteral: line))
        default:
            let names = matches.prefix(3).map { "\($0.name)（\($0.locationPath)）" }
            let extra = matches.count > 3 ? " 等 \(matches.count) 件" : ""
            return .result(dialog: IntentDialog(stringLiteral:
                "找到 \(matches.count) 件：\(names.joined(separator: "、"))\(extra)。"))
        }
    }
}

// MARK: - 问一句库存概况

struct StorageSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "问一句物品概况"
    static var description = IntentDescription("让「归位」汇报物品总数、临期数量和借出情况。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppContainer.shared)
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let expiring = items.filter { $0.expiryState == .soon || $0.expiryState == .expired }
        let lent = items.filter(\.isLentOut)

        var parts: [String] = ["你一共记了 \(items.count) 件物品"]
        parts.append(expiring.isEmpty ? "没有临期的东西" : "其中 \(expiring.count) 件临期或已过期")
        if !lent.isEmpty { parts.append("\(lent.count) 件还借在外面") }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: "，") + "。"))
    }
}

// MARK: - 快捷指令短语

/// 这些短语会自动出现在系统「快捷指令」App 和 Siri 里，用户不用自己配置。
struct GuiWeiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddItemIntent(),
                    phrases: [
                        "用\(.applicationName)记一件东西",
                        "\(.applicationName)记东西"
                    ],
                    shortTitle: "记一件物品",
                    systemImageName: "plus.square.on.square")

        AppShortcut(intent: FindItemWhereIntent(),
                    phrases: [
                        "\(.applicationName)我的东西放哪了",
                        "问\(.applicationName)东西在哪"
                    ],
                    shortTitle: "东西放哪了",
                    systemImageName: "magnifyingglass")

        AppShortcut(intent: StorageSummaryIntent(),
                    phrases: [
                        "\(.applicationName)汇报一下物品情况",
                        "\(.applicationName)有多少东西快过期了"
                    ],
                    shortTitle: "物品概况",
                    systemImageName: "chart.bar")
    }
}
