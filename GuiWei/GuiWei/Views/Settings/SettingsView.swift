import SwiftUI
import SwiftData
import UserNotifications

/// 设置页：把"和系统打交道"的部分集中起来——
/// 通知权限、Spotlight 索引、跳转「查找」、深链说明、数据重置。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var items: [Item]
    @Query private var categories: [ItemCategory]
    @Query private var spots: [StorageSpot]
    @Query private var loans: [LoanRecord]

    /// 使用者的提醒偏好，与系统权限分开存。
    @AppStorage("guiwei.remindersEnabled") private var remindersEnabled = true
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var toast: String?
    @State private var showingResetConfirm = false
    @State private var dataMode: AppDataMode = AppDataMode.current
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                ecosystemSection
                notificationSection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .task { await refreshStatus() }
            .confirmationDialog("清空全部位置和物品？",
                                isPresented: $showingClearConfirm,
                                titleVisibility: .visible) {
                Button("清空并切换到实用版", role: .destructive) {
                    apply(.practical)
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("所有物品、位置和借出记录都会被删除，分类会保留。这个操作无法撤销。")
            }
            .alert("重置为示例数据？", isPresented: $showingResetConfirm) {
                Button("取消", role: .cancel) { }
                Button("重置", role: .destructive) { resetToDemoData() }
            } message: {
                Text("当前的物品、位置和借出记录都会被清空，然后写入一份示例数据。")
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, Theme.gapL)
                        .padding(.vertical, Theme.gapM)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, Theme.gapXL)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - 生态接入

    private var ecosystemSection: some View {
        Section {
            Button {
                SpotlightIndexer.reindex(items: items)
                showToast("已把 \(items.count) 件物品写入 Spotlight")
            } label: {
                Label("重建 Spotlight 索引", systemImage: "magnifyingglass")
            }

            Label("敬请期待实体标签", systemImage: "tag")
                .foregroundStyle(.secondary)

            HStack {
                Label("借出实时活动", systemImage: "bolt.horizontal.circle")
                Spacer()
                Text(LiveActivityCenter.shared.isEnabled
                     ? "\(LiveActivityCenter.shared.activeCount) 条\u{000A}\(LiveActivityCenter.shared.lastMessage)"
                     : "系统未开启")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                showToast("Siri 说：「用归位记一件东西」")
            } label: {
                Label("看看支持哪些 Siri 指令", systemImage: "mic")
            }
        } header: {
            Text("与系统集成")
        } footer: {
            Text("物品会被索引进 Spotlight，可以直接在桌面搜索里搜到；也可以在 Siri 或快捷指令里说「用归位记一件东西」「归位我的护照放哪了」。")
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            HStack {
                Label("通知权限", systemImage: "bell")
                Spacer()
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if authStatus == .denied {
                Button("去系统设置里打开") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Toggle("临期与借出提醒", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, enabled in
                        Task { await toggleNotifications(enabled) }
                    }
            }

            HStack {
                Label("已排程提醒", systemImage: "clock")
                Spacer()
                Text("\(pendingCount) 条")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("提醒")
        } footer: {
            Text("到期前 7 天提醒一次；借出的物品在应还日当天上午提醒。通知在本地生成，不需要联网。")
        }
    }

    private var statusText: String {
        switch authStatus {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .provisional: return "临时允许"
        case .notDetermined: return "未请求"
        case .ephemeral: return "临时"
        @unknown default: return "未知"
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("外观")
        } footer: {
            Text("默认跟随系统。「自动」按时间段切换：\(AppearanceSchedule.dayStartHour):00 到 \(AppearanceSchedule.dayEndHour):00 用浅色，其余时间用深色。桌面小组件与实时活动由系统单独绘制，始终跟随系统外观，不受这里影响。")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            Picker("使用形态", selection: modeBinding) {
                ForEach(AppDataMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Text(dataMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Label("物品", systemImage: "shippingbox"); Spacer()
                Text("\(items.count)").foregroundStyle(.secondary)
            }
            HStack {
                Label("位置", systemImage: "square.grid.3x3"); Spacer()
                Text("\(spots.count)").foregroundStyle(.secondary)
            }
            HStack {
                Label("分类", systemImage: "square.grid.2x2"); Spacer()
                Text("\(categories.count)").foregroundStyle(.secondary)
            }
            HStack {
                Label("借出记录", systemImage: "person.2"); Spacer()
                Text("\(loans.count)").foregroundStyle(.secondary)
            }

            Button {
                showingResetConfirm = true
            } label: {
                Label("重置为示例数据", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("演示版预置一套示例数据，打开就有内容；实用版的位置和物品全部为空，等你从零设置。数据保存在本机的 SwiftData 数据库里，删除 App 才会清空。")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Label("版本", systemImage: "info.circle"); Spacer()
                Text("1.0 (1)").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.gapS) {
                Text("关于实体标签")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Apple 未向第三方 App 开放 AirTag 等实体标签的接口，功能上线后会在这里开放绑定。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Theme.gapXS)

            Button {
                router.showOnboarding = true
            } label: {
                Label("重新查看使用教程", systemImage: "questionmark.circle")
            }

            VStack(alignment: .leading, spacing: Theme.gapS) {
                Text("支持的链接")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("guiwei://items 打开物品页；guiwei://find 打开「找东西」；guiwei://search?q=牛奶 直接搜索；guiwei://item/<编号> 跳到某件物品。快捷指令和 Spotlight 都会用到这些链接。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Theme.gapXS)
        } header: {
            Text("关于「归位」")
        } footer: {
            Text("归位 · 记录每一件东西的物理坐标。")
        }
    }

    // MARK: - 动作

    private func refreshStatus() async {
        authStatus = await NotificationService.shared.authorizationStatus()
        pendingCount = await NotificationService.shared.pendingCount()
    }

    private func toggleNotifications(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationService.shared.requestAuthorization()
            authStatus = await NotificationService.shared.authorizationStatus()
            if granted {
                await NotificationService.shared.rescheduleExpiry(for: items)
                showToast("提醒已开启")
            } else {
                remindersEnabled = false
                showToast("没有拿到通知权限，请到系统设置里打开")
            }
        } else {
            // 真正撤销已排程的通知。之前只弹了一句提示，通知照样会响——这是实机测出来的 bug。
            NotificationService.shared.cancelAll()
            showToast("提醒已关闭，已排程的通知也已撤销")
        }
        pendingCount = await NotificationService.shared.pendingCount()
    }

    /// 形态切换：切到演示版就装载示例数据，切到实用版先确认再清空
    private var modeBinding: Binding<AppDataMode> {
        Binding(
            get: { dataMode },
            set: { newMode in
                guard newMode != dataMode else { return }
                if newMode == .practical, !items.isEmpty || !spots.isEmpty {
                    showingClearConfirm = true
                } else {
                    apply(newMode)
                }
            }
        )
    }

    private func apply(_ mode: AppDataMode) {
        switch mode {
        case .demo:
            DemoDataSeeder.loadDemoContent(context: context)
            showToast("已载入演示数据")
        case .practical:
            DemoDataSeeder.clearAllContent(context: context)
            showToast("已清空，可以从零开始")
        }
        dataMode = mode
        AppDataMode.set(mode)
        syncEcosystem()
    }

    /// 数据大变之后，把外部生态（Spotlight、小组件、通知）重新同步一遍
    private func syncEcosystem() {
        let refreshed = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        SpotlightIndexer.reindex(items: refreshed)
        WidgetBridge.publish(items: refreshed)
        Task {
            await NotificationService.shared.rescheduleExpiry(for: refreshed)
            pendingCount = await NotificationService.shared.pendingCount()
        }
    }

    private func resetToDemoData() {
        for loan in loans { context.delete(loan) }
        for item in items { context.delete(item) }
        for spot in spots { context.delete(spot) }
        for category in categories { context.delete(category) }
        try? context.save()
        DemoDataSeeder.loadDemoContent(context: context)
        dataMode = .demo
        syncEcosystem()
        showToast("已重置为示例数据")
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}
