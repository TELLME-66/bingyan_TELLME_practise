import SwiftUI
import SwiftData

@main
struct GuiWeiApp: App {
    @State private var router = AppRouter()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @State private var showOnboarding = false
    /// 这次弹出的首次启动流程要不要跳过外观选择（设置页手动唤起时为 true）
    @State private var skipAppearanceStep = false
    /// 当下实际使用的配色方案（由外观偏好解析而来，不写回偏好）
    @State private var resolvedScheme: ColorScheme?
    /// 跨过白天/夜间分界时负责重新解析
    @State private var boundaryTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .tint(Color(hex: "2E5FA3"))
                .onOpenURL { url in
                    router.handle(url)
                }
                // 外观偏好即时生效：跟随系统时交给系统，自动模式按当下时间解析
                .preferredColorScheme(resolvedScheme)
                .task { refreshAppearance() }
                .onChange(of: appearanceRaw) { _, _ in refreshAppearance() }
                .onChange(of: scenePhase) { _, phase in
                    // 从后台回来时重新解析一次：设备休眠期间定时器不会触发，
                    // 光靠定时器会出现"回到前台还是昨晚的深色"这种问题。
                    if phase == .active { refreshAppearance() }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    FirstRunFlowView(skipAppearance: skipAppearanceStep)
                }
                .onChange(of: router.showOnboarding) { _, shouldShow in
                    if shouldShow {
                        // 从设置页手动唤起：只看指南，不再问外观
                        skipAppearanceStep = true
                        showOnboarding = true
                        router.showOnboarding = false
                    }
                }
                .task {
                    await bootstrap()
                    await presentOnboardingIfNeeded()
                }
        }
        .modelContainer(AppContainer.shared)
    }

    /// 重新解析当前应该用的配色方案，并在自动模式下安排下一次切换。
    @MainActor
    private func refreshAppearance() {
        let appearance = AppAppearance(rawValue: appearanceRaw) ?? .system
        resolvedScheme = AppearanceSchedule.scheme(for: appearance)

        boundaryTask?.cancel()
        boundaryTask = nil
        guard appearance == .auto else { return }

        boundaryTask = Task {
            while !Task.isCancelled {
                let seconds = AppearanceSchedule.secondsUntilNextSwitch()
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { return }
                resolvedScheme = AppearanceSchedule.scheme(for: .auto)
            }
        }
    }

    /// 首次启动（或从设置页手动唤起）时展示使用教程。
    /// 稍微延迟一点再弹，避免和首帧渲染抢时序导致弹不出来。
    @MainActor
    private func presentOnboardingIfNeeded() async {
        #if DEBUG
        // 调试入口：跳过整个首次启动流程，直接看主界面
        if UserDefaults.standard.bool(forKey: "skipOnboarding") {
            hasCompletedOnboarding = true
            AppAppearance.hasChosen = true
            return
        }
        // 调试入口：只弹外观选择
        if UserDefaults.standard.bool(forKey: "showAppearance") {
            try? await Task.sleep(nanoseconds: 300_000_000)
            skipAppearanceStep = false
            showOnboarding = true
            return
        }
        // 调试入口：直接看新手指南
        if UserDefaults.standard.bool(forKey: "showOnboarding") {
            try? await Task.sleep(nanoseconds: 300_000_000)
            skipAppearanceStep = true
            showOnboarding = true
            return
        }
        #endif
        // 外观还没问过 → 先问外观
        if !AppAppearance.hasChosen {
            try? await Task.sleep(nanoseconds: 300_000_000)
            skipAppearanceStep = false
            showOnboarding = true
            return
        }
        guard !hasCompletedOnboarding else { return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        skipAppearanceStep = true
        showOnboarding = true
    }

    /// 启动时的准备工作：示例数据、Spotlight 索引、通知重排。
    /// 都放在 task 里做，避免阻塞首帧。
    @MainActor
    private func bootstrap() async {
        router.applyLaunchArguments()

        let container = AppContainer.shared
        let context = ModelContext(container)

        #if DEBUG
        // 调试入口：xcrun simctl launch booted <id> -dataMode demo|practical
        //
        // 注意：这里在动作结束后会把使用者原本的形态偏好放回去。
        // 调试参数只该影响这一次运行的数据，不该永久改写真实偏好——
        // 之前就是因为它把"演示版"写了进去，才导致模拟器上一直留着示例数据。
        if let raw = UserDefaults.standard.string(forKey: "dataMode"),
           let mode = AppDataMode(rawValue: raw) {
            let remembered = UserDefaults.standard.string(forKey: AppDataMode.storageKey)
            if mode == .demo {
                DemoDataSeeder.loadDemoContent(context: context)
            } else {
                DemoDataSeeder.clearAllContent(context: context)
            }
            if let remembered {
                UserDefaults.standard.set(remembered, forKey: AppDataMode.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppDataMode.storageKey)
            }
        }
        #endif

        DemoDataSeeder.seedIfNeeded(context: context)

        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        SpotlightIndexer.reindex(items: items)
        WidgetBridge.publish(items: items)
        await NotificationService.shared.rescheduleExpiry(for: items)

        #if DEBUG
        // 调试入口：xcrun simctl launch booted com.bingyan.guiwei -startLiveActivity 1
        if UserDefaults.standard.bool(forKey: "startLiveActivity"),
           let item = items.first(where: { $0.isLentOut }),
           let loan = item.activeLoan {
            LiveActivityCenter.shared.start(itemName: item.name,
                                         borrower: loan.borrower,
                                         locationPath: item.locationPath,
                                         dueDate: loan.dueAt)
        }
        #endif
    }
}
