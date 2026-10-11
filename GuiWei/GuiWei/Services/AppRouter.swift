import Foundation
import Observation

/// 深链与界面状态的路由器。
///
/// 支持的链接（也是接入系统生态的一种方式，快捷指令、分享都能用）：
/// - guiwei://items            打开物品页
/// - guiwei://spots            打开位置页
/// - guiwei://stats            打开统计页
/// - guiwei://settings         打开设置页
/// - guiwei://search?q=牛奶    打开物品页并带上搜索词
/// - guiwei://find             直接打开「找东西」面板
/// - guiwei://find?q=护照      打开面板并预填关键词
/// - guiwei://new              打开「添加物品」表单
/// - guiwei://item/<uid>       直接跳到某个物品详情
@Observable
final class AppRouter {
    enum Tab: String, Hashable, CaseIterable {
        case items, spots, stats, settings

        var title: String {
            switch self {
            case .items: return "物品"
            case .spots: return "位置"
            case .stats: return "统计"
            case .settings: return "设置"
            }
        }

        var symbolName: String {
            switch self {
            case .items: return "shippingbox"
            case .spots: return "square.grid.3x3.square"
            case .stats: return "chart.bar.xaxis"
            case .settings: return "gearshape"
            }
        }
    }

    var selectedTab: Tab = .items
    var searchQuery: String = ""
    var focusedItemUID: String?
    /// 一次性信号：置为 true 时界面打开「找东西」面板，打开后由界面复位
    var showQuickFind: Bool = false
    /// 「找东西」面板的预填关键词，例如 guiwei://find?q=护照
    var quickFindQuery: String = ""
    /// 一次性信号：打开「添加物品」表单，例如 guiwei://new
    var showNewItem: Bool = false
    /// 一次性信号：重新展示首次使用教程（设置页里可以手动唤起）
    var showOnboarding: Bool = false

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "guiwei" else { return }
        let host = (url.host ?? "").lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch host {
        case "items":
            selectedTab = .items
        case "spots":
            selectedTab = .spots
        case "stats":
            selectedTab = .stats
        case "settings":
            selectedTab = .settings
        case "search":
            selectedTab = .items
            searchQuery = components?.queryItems?.first { $0.name == "q" }?.value ?? ""
        case "find":
            selectedTab = .items
            quickFindQuery = components?.queryItems?.first { $0.name == "q" }?.value ?? ""
            showQuickFind = true
        case "new":
            selectedTab = .items
            showNewItem = true
        case "item":
            let uid = url.pathComponents.dropFirst().first ?? ""
            if !uid.isEmpty {
                selectedTab = .items
                focusedItemUID = uid
            }
        default:
            selectedTab = .items
        }
    }

    /// 启动参数入口，只在 Debug 构建里生效。
    ///
    /// 用法（模拟器）：
    /// `xcrun simctl launch booted com.bingyan.guiwei -startTab stats`
    /// 支持 -startTab / -startItem / -startFind / -startNew。
    /// 做自动化截图和复现某个具体界面时非常省事，Release 构建里不会带上。
    func applyLaunchArguments() {
        #if DEBUG
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: "startTab"),
           let tab = Tab(rawValue: raw) {
            selectedTab = tab
        }
        if let uid = defaults.string(forKey: "startItem"), !uid.isEmpty {
            selectedTab = .items
            focusedItemUID = uid
        }
        if let query = defaults.string(forKey: "startFind") {
            selectedTab = .items
            quickFindQuery = query
            showQuickFind = true
        }
        if defaults.bool(forKey: "startNew") {
            selectedTab = .items
            showNewItem = true
        }
        #endif
    }
}
