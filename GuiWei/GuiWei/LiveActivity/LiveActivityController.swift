import ActivityKit
import Foundation
import Observation
import SwiftData

/// 实时活动的唯一入口：**始终只展示「下一件要做的事」**。
///
/// 挑选规则（固定优先级）：
/// 1. **到期**：有到期日期、且已经进入提醒窗口（30 天内）或已过期的物品，取最近的一件；
/// 2. **归还**：借出去且约定过应还日期的物品，取应还最近的一件；
/// 3. 两类都没有 → 不显示，腾出灵动岛。
///
/// 什么时候刷新：
/// - App 回到前台时（此时也可以安全地**开启**活动——ActivityKit 要求前台才能 request）
/// - App 退到后台时（再更新一次内容）
/// - 借出 / 归还 / 编辑物品之后
///
/// 为什么在前台也保持活动存在：iOS 不会在 App 处于前台时把它自己的实时活动
/// 显示在灵动岛上，所以前台挂着不会有干扰；一旦用户切出去，它立刻就在那儿了。
/// 反过来，如果等退到后台才去 `Activity.request`，系统有可能拒绝。
@MainActor
@Observable
final class LiveActivityCenter {
    static let shared = LiveActivityCenter()

    /// 最近一次操作的结果，设置页会展示
    private(set) var lastMessage: String = "尚未尝试"

    /// 当前展示的是哪一类，没有则 nil
    private(set) var showingKind: GuiWeiActivityAttributes.Kind?

    private init() {}

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// 活动是否还能用。
    ///
    /// **注意 `.stale` 也算可用**——它只表示"内容可能过期"，活动本身仍在显示、仍可 update。
    /// 踩过的坑：一开始只认 `.active`，结果展示逾期物品时 staleDate 落在过去，
    /// 活动创建瞬间就变成 `.stale`，被自己的清理逻辑当成"已结束"删掉，
    /// 灵动岛于是"闪一下就没了"。
    private func isUsable(_ activity: Activity<GuiWeiActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale: return true
        default: return false
        }
    }

    var activeCount: Int {
        Activity<GuiWeiActivityAttributes>.activities.filter(isUsable).count
    }

    private var currentActivity: Activity<GuiWeiActivityAttributes>? {
        Activity<GuiWeiActivityAttributes>.activities.first(where: isUsable)
    }



    // MARK: - 挑选「下一件要做的事」

    /// 挑出来的结果
    struct NextUp {
        let kind: GuiWeiActivityAttributes.Kind
        let item: Item
        let date: Date
        /// 同类一共有几件
        let pendingCount: Int
    }

    /// 到期窗口：30 天内算「要到期」。与 App 里 `expiryState == .soon` 保持一致。
    static let expiryWindowDays = 30

    static func nextUp(in items: [Item]) -> NextUp? {
        // ---------- 优先级 1：到期 ----------
        let expiring = items
            .filter { item in
                guard let days = item.daysUntilExpiry else { return false }
                return days <= expiryWindowDays
            }
            .sorted { ($0.daysUntilExpiry ?? .max) < ($1.daysUntilExpiry ?? .max) }

        if let head = expiring.first, let date = head.expireDate {
            return NextUp(kind: .expiry, item: head, date: date, pendingCount: expiring.count)
        }

        // ---------- 优先级 2：归还 ----------
        let toReturn = items
            .filter { $0.activeLoan?.dueAt != nil }
            .sorted {
                ($0.activeLoan?.dueAt ?? .distantFuture) < ($1.activeLoan?.dueAt ?? .distantFuture)
            }

        if let head = toReturn.first, let date = head.activeLoan?.dueAt {
            return NextUp(kind: .loan, item: head, date: date, pendingCount: toReturn.count)
        }

        return nil
    }

    /// 活动内容的「可能过期时间」。
    ///
    /// 绝不能直接用到期日：选中一件**已经逾期**的物品时那是个过去时间，
    /// 活动会在创建瞬间被标记为过期。这里保证它至少是未来 2 小时。
    private static func staleDate(for due: Date) -> Date {
        max(due, Date.now.addingTimeInterval(2 * 3600))
    }

    // MARK: - 刷新

    /// 根据当前数据刷新灵动岛。没有要处理的事就自动收起。
    func refresh(items: [Item]) {
        guard isEnabled else {
            lastMessage = "系统未开启实时活动"
            return
        }

        guard let next = Self.nextUp(in: items) else {
            Task {
                await endAllActivities()
                showingKind = nil
                lastMessage = "暂无待办，已收起"
            }
            return
        }

        let state = GuiWeiActivityAttributes.ContentState(
            dueDate: next.date,
            pendingCount: next.pendingCount
        )
        let subtitle: String
        let location: String
        switch next.kind {
        case .expiry:
            subtitle = next.item.locationPath
            location = ""
        case .loan:
            subtitle = next.item.activeLoan?.borrower ?? "借出中"
            location = next.item.locationPath
        }

        // 已经有活动 → 原地更新；否则新建
        if let existing = currentActivity {
            Task {
                await existing.update(ActivityContent(state: state, staleDate: Self.staleDate(for: next.date)))
                showingKind = next.kind
                lastMessage = next.kind == .expiry
                    ? "正在提醒「\(next.item.name)」到期"
                    : "正在提醒「\(next.item.name)」归还"
            }
            return
        }

        let attributes = GuiWeiActivityAttributes(
            kind: next.kind,
            title: next.item.name,
            subtitle: subtitle,
            locationPath: location
        )
        // 先清掉"已结束但还没被系统移除"的旧活动。
        // 否则它们会和新活动并存，灵动岛会退化成最简态（只剩一个图标）。
        Task { await dismissFinished() }

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Self.staleDate(for: next.date)),
                pushType: nil
            )
            showingKind = next.kind
            lastMessage = next.kind == .expiry
                ? "正在提醒「\(next.item.name)」到期"
                : "正在提醒「\(next.item.name)」归还"
        } catch {
            lastMessage = "开启失败：\(error.localizedDescription)"
        }
    }

    /// 便捷入口：自己去数据库取最新物品再刷新。
    /// 借出 / 归还 / 编辑之后直接调它，调用点不用关心数据从哪来。
    func refreshFromStore() {
        let context = ModelContext(AppContainer.shared)
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        refresh(items: items)
    }

    // MARK: - 收尾

    /// 清掉真正结束了的活动（`.ended` / `.dismissed`）。
    /// **不要碰 `.stale`**——那还是正在显示的活动。
    private func dismissFinished() async {
        for activity in Activity<GuiWeiActivityAttributes>.activities
        where !isUsable(activity) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func endAllActivities() async {
        for activity in Activity<GuiWeiActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endAll() {
        Task {
            await endAllActivities()
            showingKind = nil
            lastMessage = "已收起"
        }
    }

    /// 回到前台时校正一次状态
    func syncState() {
        showingKind = currentActivity?.attributes.kind
    }
}
