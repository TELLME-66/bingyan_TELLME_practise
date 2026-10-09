import Foundation
import UserNotifications

/// 本地通知：临期提醒与借用到期提醒。
///
/// 设计原则：**不主动弹权限框**。
/// 只有用户在设置页打开开关时才请求授权；其余场合只在已授权的前提下静默排程。
/// 这样用户第一次打开 App 不会被权限弹窗打断，也符合 Apple 的审核要求。
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let expiryPrefix = "expiry-"
    private let loanPrefix = "loan-"

    private init() {}

    // MARK: - 权限

    // MARK: - 使用者偏好

    private static let preferenceKey = "guiwei.remindersEnabled"

    /// 使用者是否希望收到提醒（与系统权限是两件事）。默认开启。
    static var remindersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    /// 撤销所有已排程与已送达的提醒。
    /// 关掉开关时必须真正调用它，否则已经排好的通知照样会响。
    func cancelAll() {
        let center = UNUserNotificationCenter.current()
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

    // MARK: - 排程

    /// 早于这个天数就提醒
    static let reminderLeadDays = 7

    /// 根据当前全部物品重排临期通知：先清空旧的，再按需重建，避免重复
    func rescheduleExpiry(for items: [Item]) async {
        // 使用者关掉提醒后，启动时不要再偷偷排回去
        guard Self.remindersEnabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: items.map { expiryPrefix + $0.uid })
        for item in items {
            await scheduleExpiry(for: item)
        }
    }

    func scheduleExpiry(for item: Item) async {
        guard let expireDate = item.expireDate else { return }
        center.removePendingNotificationRequests(withIdentifiers: [expiryPrefix + item.uid])

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

    func cancelExpiry(for item: Item) {
        center.removePendingNotificationRequests(withIdentifiers: [expiryPrefix + item.uid])
    }

    /// 借用到期提醒：到期当天上午 10 点提醒
    func scheduleLoanDue(for loan: LoanRecord) async {
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
}
