import WidgetKit
import SwiftUI

// MARK: - 时间线

struct GuiWeiEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct GuiWeiProvider: TimelineProvider {
    func placeholder(in context: Context) -> GuiWeiEntry {
        GuiWeiEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (GuiWeiEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.preview : WidgetStore.load()
        completion(GuiWeiEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GuiWeiEntry>) -> Void) {
        let entry = GuiWeiEntry(date: .now, snapshot: WidgetStore.load())
        // App 每次数据变化都会刷新快照；这里再兜一个半小时的定时刷新
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
    }
}

// MARK: - 界面

struct GuiWeiWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GuiWeiEntry

    private var urgentCount: Int {
        entry.snapshot.expiringCount + entry.snapshot.expiredCount
    }

    var body: some View {
        Group {
            if family == .systemSmall { smallView } else { mediumView }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "guiwei://items"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill").font(.caption2)
                Text("归位").font(.caption).fontWeight(.semibold)
            }
            .foregroundStyle(.secondary)

            Text("\(urgentCount)")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(urgentCount > 0 ? Color.orange : Color.green)

            Text(urgentCount > 0 ? "件东西快到期" : "没有临期的东西")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let first = entry.snapshot.lines.first {
                Text(first.name).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill").font(.caption2)
                    Text("归位").font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)

                Text("\(urgentCount)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(urgentCount > 0 ? Color.orange : Color.green)

                Text("件临期或已过期").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("共 \(entry.snapshot.totalKinds) 种 · \(entry.snapshot.totalQuantity) 个")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(width: 108, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if entry.snapshot.lines.isEmpty {
                    Text("还没有记录会过期的东西")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(entry.snapshot.lines) { line in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(line.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 0)
                                if let days = line.days {
                                    Text(days < 0 ? "已过期" : "\(days) 天")
                                        .font(.caption2)
                                        .foregroundStyle(days <= 3 ? Color.orange : Color.secondary)
                                }
                            }
                            Text(line.place)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 小组件声明

struct GuiWeiWidget: Widget {
    let kind: String = "GuiWeiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GuiWeiProvider()) { entry in
            GuiWeiWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("归位 · 临期提醒")
        .description("看看有多少东西快到期了，以及它们放在哪。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
