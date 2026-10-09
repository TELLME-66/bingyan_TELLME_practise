import Foundation
import SwiftData

/// 全 App 共用的数据容器。
/// App 本体和 App Intents（Siri／快捷指令）都从这里取同一个容器，
/// 这样语音添加的物品会立刻出现在界面里。
enum AppContainer {
    static let schema = Schema([
        Item.self,
        StorageSpot.self,
        ItemCategory.self,
        LoanRecord.self
    ])

    static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }
        // 再试一次。首次失败可能只是瞬时 I/O 问题（例如刚被系统回收、
        // 或 App 被强杀时 WAL 还没写完），不该立刻牺牲使用者的数据。
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 连续两次都打不开，通常是数据模型变更过（例如删掉了不再使用的字段）。
            // 这时才删掉本地库重建，保证最坏情况只丢一次数据，而不是每次启动都失败。
            let storeURL = config.url
            for suffix in ["", "-wal", "-shm"] {
                let target = URL(fileURLWithPath: storeURL.path + suffix)
                try? FileManager.default.removeItem(at: target)
            }
            if let rebuilt = try? ModelContainer(for: schema, configurations: [config]) {
                return rebuilt
            }
            // 最后的兜底：退回内存库，App 仍然可用，不会闪退
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()
}
