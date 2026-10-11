import Foundation
import UserNotifications

/// 本地通知：临期提醒、借用到期提醒，以及演示用的一次性通知。
///
/// 设计原则：**不主动弹权限框**。
/// 只有用户在设置页打开开关（或点演示按钮）时才请求授权；
/// 其余场合只在已授权的前提下静默排程。
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let expiryPrefix = "expiry-"
    private let loanPrefix = "loan-"
    private let summaryID = "expiry-summary"
    private let demoID = "demo-now"

    private override init() {
        super.init()
    }

    // MARK: - 代理

    /// **必须在 App 启动阶段调用一次。**
    ///
    /// 不设代理的话，App 处于前台时系统会把通知**静默丢弃**（不弹横幅、不响铃），
    /// 只有退到后台或锁屏才看得到。这正是"演示时看不到通知"的根因。
    nonisolated func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// 前台也照常显示横幅、播放声音、进通知中心
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 点击通知时打开 App（深链交给系统按 URL Scheme 处理）
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // 目前只需把 App 带到前台；具体跳转由用户自行浏览
    }

    // MARK: - 使用者偏好

    private static let preferenceKey = "guiwei.remindersEnabled"
    private static let lastSummaryKey = "guiwei.lastUrgentSummary"

    /// 使用者是否希望收到提醒（与系统权限是两件事）。默认开启。
    static var remindersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    /// 撤销所有已排程与已送达的提醒
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 确保有权限；没有就当场要一次。
    ///
    /// **只在用户主动触发的路径上调用**（打开提醒开关、点「立刻发一条通知」），
    /// 不要放进启动流程，否则每次启动都会弹权限框。
    @discardableResult
    func ensureAuthorized() async -> Bool {
        let status = await authorizationStatus()
        if status == .authorized || status == .provisional { return true }
        if status == .denied { return false }
        return await requestAuthorization()
    }

    // MARK: - 排程

    /// 早于这个天数就提醒
    static let reminderLeadDays = 7

    /// 根据当前全部物品重排临期通知：先清空旧的，再按需重建，避免重复。
    ///
    /// 分两条路：
    /// 1. 还在提醒窗口**之外**的 → 按「到期前 7 天」排一个日历通知；
    /// 2. 已经进入窗口**之内**（含已过期）的 → 合并成一条摘要，**当天只发一次**。
    ///
    /// 第 2 条是修掉的一个真实缺陷：以前这些物品因为触发时间已过，
    /// `guard fireDate > .now` 直接失败，结果**一条通知都排不出来**。
    func rescheduleExpiry(for items: [Item]) async {
        guard Self.remindersEnabled else { return }
        // 这里**不主动请求权限**：只有用户在设置页打开开关或点演示按钮时才要。
        // 否则每次启动都会弹一次系统框，既打断用户也不符合 Apple 的建议。
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: items.map { expiryPrefix + $0.uid })
        center.removePendingNotificationRequests(withIdentifiers: [summaryID])

        for item in items {
            await scheduleExpiry(for: item)
        }

        let urgent = items.filter { item in
            (item.daysUntilExpiry).map { $0 <= Self.reminderLeadDays } ?? false
        }
        guard !urgent.isEmpty else { return }

        // 当天已经提醒过就不再打扰
        if let last = UserDefaults.standard.object(forKey: Self.lastSummaryKey) as? Date,
           Calendar.current.isDateInToday(last) {
            return
        }
        await scheduleUrgentSummary(urgent)
        UserDefaults.standard.set(Date.now, forKey: Self.lastSummaryKey)
    }

    func scheduleExpiry(for item: Item) async {
        guard let expireDate = item.expireDate else { return }
        center.removePendingNotificationRequests(withIdentifiers: [expiryPrefix + item.uid])

        // 触发时间 = 到期前 7 天。已经过了或就在眼前，就交给摘要通知，不在这里重复排
        guard let fireDate = Calendar.current.date(byAdding: .day,
                                                   value: -Self.reminderLeadDays,
                                                   to: expireDate),
              fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "「\(item.name)」快到期了"
        content.body = "\(item.locationPath) · 还有 \(Self.reminderLeadDays) 天到期"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour],
                                                         from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: expiryPrefix + item.uid,
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    /// 把已经进入提醒窗口的物品合并成一条摘要，5 秒后送达
    private func scheduleUrgentSummary(_ urgent: [Item]) async {
        let content = UNMutableNotificationContent()
        let head = urgent.prefix(3).map { item -> String in
            if let text = item.expiryText { return "\(item.name)（\(text)）" }
            return item.name
        }
        content.title = urgent.count == 1
            ? "「\(urgent[0].name)」该处理了"
            : "有 \(urgent.count) 件东西要到期了"
        content.body = head.joined(separator: "、")
            + (urgent.count > 3 ? " 等" : "")
        content.sound = .default
        content.userInfo = ["route": "guiwei://items"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: summaryID,
                                                    content: content,
                                                    trigger: trigger))
    }

    func cancelExpiry(for item: Item) {
        center.removePendingNotificationRequests(withIdentifiers: [expiryPrefix + item.uid])
    }

    /// 借用到期提醒：到期当天上午 10 点提醒
    func scheduleLoanDue(for loan: LoanRecord) async {
        // 同样不主动要权限
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        guard let dueAt = loan.dueAt, let item = loan.item else { return }

        let identifier = loanPrefix + item.uid
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard dueAt > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "该把「\(item.name)」要回来了"
        content.body = "\(loan.borrower) 借走的物品今天到期"
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day], from: dueAt)
        components.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelLoan(for itemUID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [loanPrefix + itemUID])
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    // MARK: - 演示用

    /// 立刻发一条通知（3 秒后送达），用于演示与自测。
    ///
    /// 内容优先取当前最紧急的真实物品，没有数据时用一条示例。
    /// 返回 false 表示没拿到通知权限。
    @discardableResult
    func sendDemoNotification(using items: [Item], delay: TimeInterval = 3) async -> Bool {
        guard await ensureAuthorized() else { return false }

        let urgent = items
            .filter { ($0.daysUntilExpiry).map { $0 <= Self.reminderLeadDays } ?? false }
            .sorted { ($0.daysUntilExpiry ?? .max) < ($1.daysUntilExpiry ?? .max) }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["route": "guiwei://items"]
        content.threadIdentifier = "guiwei-demo"

        if let head = urgent.first {
            content.title = "「\(head.name)」\(head.expiryText ?? "快到期了")"
            content.body = "\(head.locationPath)"
                + (urgent.count > 1 ? " · 另有 \(urgent.count - 1) 件需要关注" : "")
        } else {
            content.title = "「全脂牛奶」快到期了"
            content.body = "厨房 › 冰箱 › 冷藏层 · 还有 3 天到期"
        }

        // 先清掉上一条演示通知，避免连点堆叠
        center.removePendingNotificationRequests(withIdentifiers: [demoID])
        center.removeDeliveredNotifications(withIdentifiers: [demoID])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: demoID,
                                                       content: content,
                                                       trigger: trigger))
            return true
        } catch {
            return false
        }
    }
}
