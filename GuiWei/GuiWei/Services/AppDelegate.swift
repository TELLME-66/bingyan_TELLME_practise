import ActivityKit
import UIKit

/// 只做一件事：**争取在 App 被划掉时把灵动岛收起来**。
///
/// 背景：
/// - App 处于**挂起**状态时被从后台划掉，`applicationWillTerminate` **不会被调用**；
/// - 只有 App 还在后台**运行**时被划掉，才会走到它。
///
/// 所以我们进入后台时申请一小段后台执行时间（iOS 通常给约 30 秒）。
/// 在这段时间内划掉 App，就能收到回调并结束实时活动；
/// 超过这段时间 App 被挂起，就只能靠用户在灵动岛里点「知道了」，
/// 或者从设置页的「收起灵动岛」手动清理。
///
/// 这是平台限制下的折中，不是完整解——iOS 没有提供"用户划掉 App"的可靠信号。
final class AppDelegate: NSObject, UIApplicationDelegate {

    private var keepAliveTask: UIBackgroundTaskIdentifier = .invalid

    func applicationDidEnterBackground(_ application: UIApplication) {
        endKeepAlive(application)
        keepAliveTask = application.beginBackgroundTask(withName: "guiwei.keepalive") { [weak self] in
            guard let self else { return }
            self.endKeepAlive(application)
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        endKeepAlive(application)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // 这里要尽量同步地收尾：进程随时会被杀掉，所以用一个信号量等一小会儿。
        //
        // **必须用 Task.detached**：如果写成 `Task { }`，任务会排到主 actor 上，
        // 而下面 `semaphore.wait` 正好把主线程堵死了 —— 任务永远轮不到执行，
        // 必然超时，活动也就没被结束。这是踩过的坑。
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in Activity<GuiWeiActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        endKeepAlive(application)
    }

    private func endKeepAlive(_ application: UIApplication) {
        guard keepAliveTask != .invalid else { return }
        application.endBackgroundTask(keepAliveTask)
        keepAliveTask = .invalid
    }
}
