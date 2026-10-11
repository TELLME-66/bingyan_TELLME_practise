import SwiftUI
import SwiftData

/// 物品列表：App 的主界面。
/// 承载了题目里"查看、搜索、筛选、分类"四条要求。
struct ItemListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @Query(sort: \Item.updatedAt, order: .reverse) private var items: [Item]
    @Query(sort: \ItemCategory.sortIndex) private var categories: [ItemCategory]
    /// 只用来判断"有没有建过位置"，决定空状态该引导用户做什么
    @Query private var spots: [StorageSpot]

    @State private var path: [Item] = []
    @State private var sortMode: SortMode = .recent
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedCategory: ItemCategory?
    @State private var showingEditor = false
    @State private var showingQuickFind = false
    @State private var pendingDeletion: Item?
    /// 借出表单的呈现对象。只要它非空，sheet 就带着完整数据出现。
    @State private var lendingItem: Item?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Color(.systemGroupedBackground))
            // 这里刻意不用系统的「大标题 + .searchable」组合：
            // 它在滚动/转场时会让大标题和搜索框叠在一起（真机上复现过，
            // 属于 SwiftUI 自己的布局协调问题）。改成自绘头部后彻底没有这个状态。
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .sheet(isPresented: $showingEditor) {
                ItemEditorView(item: nil)
                    .appSheetRadius()
            }
            .sheet(isPresented: $showingQuickFind) {
                QuickFindView(initialQuery: router.quickFindQuery)
                    .appSheetRadius()
            }
            // 用 sheet(item:) 而不是 sheet(isPresented:) + 可选的 item。
            // 后者是两个独立的状态，滑动操作里两次赋值可能不在同一个更新事务里，
            // 于是 sheet 先被呈现、item 还是 nil，就会出现一张空白表单。
            .sheet(item: $lendingItem) { item in
                LendSheet(item: item)
                    .appSheetRadius()
            }
            .alert("删除这件物品？",
                   isPresented: Binding(get: { pendingDeletion != nil },
                                        set: { if !$0 { pendingDeletion = nil } })) {
                Button("取消", role: .cancel) { pendingDeletion = nil }
                Button("删除", role: .destructive) {
                    if let item = pendingDeletion { delete(item) }
                    pendingDeletion = nil
                }
            } message: {
                Text(pendingDeletion.map { "「\($0.name)」的记录会被移除，无法恢复。" } ?? "")
            }
            .onChange(of: router.focusedItemUID) { _, uid in
                focusItem(with: uid)
            }
            .onChange(of: router.searchQuery) { _, query in
                if !query.isEmpty { searchText = query }
            }
            // 下面这些用 task(id:) 而不是 onChange：
            // 深链和启动参数可能在视图出现之前就把状态设好了，
            // onChange 只在值"变化"时触发，会漏掉这种情况。
            #if DEBUG
            // 调试入口：xcrun simctl launch booted <id> -openLendSheet 1
            // 用来验证「右滑借出」这条路径本身（走的和真实滑动完全相同的代码）
            .task {
                if UserDefaults.standard.bool(forKey: "openLendSheet"),
                   lendingItem == nil,
                   let first = items.first {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    lendingItem = first
                }
            }
            #endif
            .task(id: router.showQuickFind) {
                if router.showQuickFind {
                    showingQuickFind = true
                    router.showQuickFind = false
                }
            }
            .task(id: router.showNewItem) {
                if router.showNewItem {
                    showingEditor = true
                    router.showNewItem = false
                }
            }
            .task(id: router.focusedItemUID) {
                // 冷启动时数据可能还没从数据库读回来，这里做有限次重试
                guard let uid = router.focusedItemUID else { return }
                for _ in 0..<20 {
                    if let match = items.first(where: { $0.uid == uid }) {
                        path = [match]
                        router.focusedItemUID = nil
                        return
                    }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
        }
    }

    // MARK: - 搜索（用内存过滤，避免 #Predicate 无法表达中文包含判断）

    @State private var searchText = ""

    private func focusItem(with uid: String?) {
        guard let uid, let match = items.first(where: { $0.uid == uid }) else { return }
        path = [match]
        router.focusedItemUID = nil
    }

    // MARK: - 筛选与排序

    private var visibleItems: [Item] {
        var result = items

        switch statusFilter {
        case .all:
            break
        case .expiring:
            result = result.filter { $0.expiryState == .soon || $0.expiryState == .expired }
        case .lent:
            result = result.filter(\.isLentOut)
        case .favorite:
            result = result.filter(\.isFavorite)
        }

        if let selectedCategory {
            result = result.filter { $0.category?.persistentModelID == selectedCategory.persistentModelID }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let keyword = searchText.trimmingCharacters(in: .whitespaces)
            result = result.filter { item in
                item.name.localizedStandardContains(keyword)
                    || item.locationPath.localizedStandardContains(keyword)
                    || item.tags.contains { $0.localizedStandardContains(keyword) }
                    || (item.category?.name.localizedStandardContains(keyword) ?? false)
                    || (item.note?.localizedStandardContains(keyword) ?? false)
            }
        }

        switch sortMode {
        case .recent:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .expiry:
            result.sort { lhs, rhs in
                let l = lhs.daysUntilExpiry ?? Int.max
                let r = rhs.daysUntilExpiry ?? Int.max
                if l == r { return lhs.name < rhs.name }
                return l < r
            }
        case .name:
            result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .quantity:
            result.sort { $0.quantity > $1.quantity }
        }
        return result
    }

    // MARK: - 界面

    /// 顶部固定区：标题、三个操作按钮、搜索框、筛选条。
    /// 全部由我们自己绘制，不依赖系统导航栏，因此不存在标题与搜索框重叠的状态。
    private var header: some View {
        VStack(spacing: Theme.gapM) {
            HStack(spacing: Theme.gapL) {
                Text("归位")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer(minLength: 0)

                Button {
                    showingQuickFind = true
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.title2)
                }
                .accessibilityLabel("找东西")

                Menu {
                    Picker("排序", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.title3)
                }
                .accessibilityLabel("排序")

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                }
                .accessibilityLabel("添加物品")
            }
            .padding(.horizontal, Theme.gapL)

            searchField

            filterBar
        }
        .padding(.top, Theme.gapS)
        .padding(.bottom, Theme.gapS)
        .background(Color(.systemGroupedBackground))
    }

    private var searchField: some View {
        HStack(spacing: Theme.gapS) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜物品、位置或标签", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, Theme.gapM)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
        .padding(.horizontal, Theme.gapL)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.gapS) {
                ForEach(StatusFilter.allCases) { filter in
                    chip(title: filter.title,
                         symbol: filter.symbol,
                         selected: statusFilter == filter) {
                        statusFilter = filter
                    }
                }

                Divider().frame(height: 20)

                Menu {
                    Button("全部分类") { selectedCategory = nil }
                    Divider()
                    ForEach(categories) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Label(category.name, systemImage: category.symbolName)
                        }
                    }
                } label: {
                    chipLabel(title: selectedCategory?.name ?? "全部分类",
                              symbol: "line.3.horizontal.decrease.circle",
                              selected: selectedCategory != nil)
                }
            }
            .padding(.horizontal, Theme.gapL)
            .padding(.vertical, Theme.gapS)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title: title, symbol: symbol, selected: selected) }
            .buttonStyle(.plain)
    }

    private func chipLabel(title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: Theme.gapXS) {
            Image(systemName: symbol).font(.caption)
            Text(title).font(.subheadline)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, Theme.gapM)
        .padding(.vertical, 7)
        .background(selected ? Color(hex: "2E5FA3") : Color(.secondarySystemGroupedBackground),
                    in: Capsule())
    }

    @ViewBuilder
    private var content: some View {
        if visibleItems.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(emptyMessage)
            } actions: {
                if searchText.isEmpty && statusFilter == .all && selectedCategory == nil {
                    Button("添加第一件物品") { showingEditor = true }
                        .buttonStyle(.borderedProminent)
                        .appButtonShape()
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        } else {
            List {
                ForEach(visibleItems) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item)
                    }
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletion = item
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            toggleFavorite(item)
                        } label: {
                            Label(item.isFavorite ? "取消收藏" : "收藏",
                                  systemImage: item.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if item.isLentOut {
                            Button { returnItem(item) } label: {
                                Label("已归还", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        } else {
                            Button { lendAction(item) } label: {
                                Label("借出", systemImage: "person.badge.plus")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "没有匹配的物品" }
        if statusFilter != .all { return "这里暂时是空的" }
        if selectedCategory != nil { return "这个分类下还没有物品" }
        return "还没有记录任何物品"
    }

    private var emptySymbol: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return "shippingbox"
    }

    private var emptyMessage: String {
        if !searchText.isEmpty { return "换个关键词，或者清空搜索条件再试试。" }
        if statusFilter != .all { return "换一个筛选条件看看。" }
        // 刚开始使用时还没有任何位置，先引导把「房间 › 容器 › 格位」建起来，
        // 否则添加物品时选不到存放位置。
        if spots.isEmpty {
            return "先到「位置」页建一个房间和容器，再回来记录东西放在哪。"
        }
        return "记录一件东西放在哪，下次就不用翻箱倒柜。"
    }


    // MARK: - 操作

    private func toggleFavorite(_ item: Item) {
        item.isFavorite.toggle()
        item.touch()
        try? context.save()
    }

    private func delete(_ item: Item) {
        NotificationService.shared.cancelExpiry(for: item)
        NotificationService.shared.cancelLoan(for: item.uid)
        context.delete(item)
        try? context.save()
        refreshEcosystem()
    }

    private func lendAction(_ item: Item) {
        lendingItem = item
    }

    private func returnItem(_ item: Item) {
        if let loan = item.activeLoan {
            loan.returnedAt = .now
            item.touch()
            try? context.save()
            NotificationService.shared.cancelLoan(for: item.uid)
            LiveActivityCenter.shared.refreshFromStore()
            refreshEcosystem()
        }
    }

    /// 数据变化后同步外部生态：小组件快照。
    /// 这里重新从上下文取一次，而不是用 @Query 的 items——
    /// 删除后 @Query 还没来得及刷新，会把已删除的物品又写回索引和快照。
    private func refreshEcosystem() {
        let current = (try? context.fetch(FetchDescriptor<Item>())) ?? items
        WidgetBridge.publish(items: current)
    }
}

// MARK: - 辅助类型

enum SortMode: String, CaseIterable, Identifiable {
    case recent, expiry, name, quantity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近更新"
        case .expiry: return "按到期时间"
        case .name: return "按名称"
        case .quantity: return "按数量"
        }
    }

    var symbol: String {
        switch self {
        case .recent: return "clock"
        case .expiry: return "calendar"
        case .name: return "textformat"
        case .quantity: return "number"
        }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all, expiring, lent, favorite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .expiring: return "临期"
        case .lent: return "借出中"
        case .favorite: return "收藏"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .expiring: return "clock.badge.exclamationmark"
        case .lent: return "person.2"
        case .favorite: return "star"
        }
    }
}
