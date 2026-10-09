import ActivityKit
import Foundation
import Observation

/// 实时活动的开关与更新。
///
/// 用在哪：借出一件东西时，在灵动岛和锁定屏上显示"借给谁、还剩几天"。
/// 这是实时活动最典型的用法——一个有时限、用户会时不时瞄一眼的状态。
///
/// 做成 `@Observable` 单例，是为了让设置页能实时反映"到底开没开起来"，
/// 而不是渲染一次就定格在初始值上（这是排查时踩过的坑）。
@MainActor
@Observable
final class LiveActivityCenter {
    static let shared = LiveActivityCenter()

    /// 最近一次尝试的结果，设置页会展示它
    private(set) var lastMessage: String = "尚未尝试"

    /// 当前设备/系统是否允许实时活动
    var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var activeCount: Int {
        Activity<GuiWeiActivityAttributes>.activities.count
    }

    private init() {}

    /// 借出时启动
    func start(itemName: String, borrower: String, locationPath: String, dueDate: Date?) {
        guard isEnabled else {
            lastMessage = "系统未开启实时活动"
            return
        }
        endAll(matching: itemName)

        let attributes = GuiWeiActivityAttributes(itemName: itemName,
                                                  borrower: borrower,
                                                  locationPath: locationPath)
        let state = GuiWeiActivityAttributes.ContentState(dueDate: dueDate, isReturned: false)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            lastMessage = "已开启（\(activity.id.prefix(8))）"
        } catch {
            // 实时活动失败不影响主流程，但把原因留在设置页可查
            lastMessage = "开启失败：\(error.localizedDescription)"
        }
    }

    /// 归还时结束
    func finish(itemName: String) {
        Task {
            for activity in Activity<GuiWeiActivityAttributes>.activities
            where activity.attributes.itemName == itemName {
                var state = activity.content.state
                state.isReturned = true
                await activity.end(ActivityContent(state: state, staleDate: nil),
                                   dismissalPolicy: .after(.now.addingTimeInterval(8)))
            }
            lastMessage = "已结束"
        }
    }

    func endAll(matching itemName: String? = nil) {
        Task {
            for activity in Activity<GuiWeiActivityAttributes>.activities {
                if let itemName, activity.attributes.itemName != itemName { continue }
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
