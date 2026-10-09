import Foundation

/// 两种使用形态。
///
/// - `demo`（演示版）：第一次打开就带一整套示例数据，用于展示、汇报、截图。
/// - `practical`（实用版）：位置和物品都是空的，使用者从零建立自己的体系。
///
/// 默认值由编译条件 `DEMO_DATA` 决定，因此可以构建出两个真正独立的 App
/// （Bundle ID 不同，能并排装在同一台手机上）；设置页里也能随时切换形态，
/// 方便一个人两种场景都用同一个包。
enum AppDataMode: String, CaseIterable, Identifiable {
    case practical
    case demo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: return "演示版"
        case .practical: return "实用版"
        }
    }

    var detail: String {
        switch self {
        case .demo: return "预置一套示例数据，打开就有内容可看。"
        case .practical: return "位置与物品全部为空，等待你自己设定。"
        }
    }

    var symbol: String {
        switch self {
        case .demo: return "sparkles"
        case .practical: return "square.and.pencil"
        }
    }

    // MARK: - 持久化

    /// 使用者选择的存储键。调试参数会在用完它之后还原，避免污染真实偏好。
    static let storageKey = "guiwei.dataMode"
    private static let demoLoadedKey = "guiwei.demoDataLoaded"

    /// 当前形态：优先读使用者的选择，没有则用构建时定的默认值
    static var current: AppDataMode {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let mode = AppDataMode(rawValue: raw) {
            return mode
        }
        #if DEMO_DATA
        return .demo
        #else
        return .practical
        #endif
    }

    static func set(_ mode: AppDataMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey)
    }

    /// 示例数据是否已经装载过。
    /// 有这个标记，用户在演示版里把东西全删了，下次启动也不会又自动长回来。
    static var hasLoadedDemoData: Bool {
        get { UserDefaults.standard.bool(forKey: demoLoadedKey) }
        set { UserDefaults.standard.set(newValue, forKey: demoLoadedKey) }
    }
}
