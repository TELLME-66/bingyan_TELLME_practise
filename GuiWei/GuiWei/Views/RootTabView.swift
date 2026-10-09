import SwiftUI

/// 根视图：四个页签，各自包一层 NavigationStack，互不干扰浏览历史。
struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ItemListView()
                .tabItem { Label(AppRouter.Tab.items.title,
                                 systemImage: AppRouter.Tab.items.symbolName) }
                .tag(AppRouter.Tab.items)

            SpotListView()
                .tabItem { Label(AppRouter.Tab.spots.title,
                                 systemImage: AppRouter.Tab.spots.symbolName) }
                .tag(AppRouter.Tab.spots)

            StatsView()
                .tabItem { Label(AppRouter.Tab.stats.title,
                                 systemImage: AppRouter.Tab.stats.symbolName) }
                .tag(AppRouter.Tab.stats)

            SettingsView()
                .tabItem { Label(AppRouter.Tab.settings.title,
                                 systemImage: AppRouter.Tab.settings.symbolName) }
                .tag(AppRouter.Tab.settings)
        }
    }
}
