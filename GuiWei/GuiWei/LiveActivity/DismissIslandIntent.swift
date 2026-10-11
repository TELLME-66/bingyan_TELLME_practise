import ActivityKit
import AppIntents

/// 收起灵动岛。
///
/// **这个定义必须同时存在于 App target 和小组件扩展 target 里**：
/// - 扩展那一份让灵动岛能把按钮画出来；
/// - **App 这一份才是真正干活的** —— `LiveActivityIntent` 由系统在 App 的进程里执行，
///   如果 App 的 App Intents 元数据里没有登记它，点击就毫无反应。
///
/// 踩过的坑：一开始只写在扩展里，结果按钮能看见、点了没反应。
/// 用 `strings GuiWei.app/Metadata.appintents/extract.actionsdata` 才查出根因。
struct DismissIslandIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "收起灵动岛"
    static var description = IntentDescription("把归位的实时活动从灵动岛和锁定屏上移除。")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        for activity in Activity<GuiWeiActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
