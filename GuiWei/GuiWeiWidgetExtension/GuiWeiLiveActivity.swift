import ActivityKit
import WidgetKit
import SwiftUI

/// 借出追踪的实时活动：同时提供锁定屏样式与灵动岛样式。
///
/// 关于灵动岛的尺寸适配（iPhone 17 Pro 与 18 Pro 的灵动岛宽度不同）：
/// 1. 紧凑态（compactLeading / compactTrailing）与最简态（minimal）只放
///    「一个图标 + 最多三个字」，任何机型的灵动岛都放得下，不会被裁切；
/// 2. 展开态里较长的内容用 `.dynamicIsland(verticalPlacement: .belowIfTooWide)`，
///    当灵动岛宽度不够时系统会自动把它放到下方一行，而不是硬挤；
/// 3. 需要完整信息的场景交给锁定屏样式，那里的宽度不受灵动岛限制。
struct GuiWeiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuiWeiActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(WidgetTheme.cardBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("借出中", systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(WidgetTheme.accent)
                        .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.shortText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(WidgetTheme.accent)
                        .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.itemName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("借给 \(context.attributes.borrower) · \(context.state.statusText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("归还后放回：\(context.attributes.locationPath)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 灵动岛不够宽时，这块内容自动落到下方一行，避免被挤压
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
            } compactLeading: {
                Image(systemName: "person.fill")
                    .foregroundStyle(WidgetTheme.accent)
            } compactTrailing: {
                // 只放「3天」「逾期」这类短文案，保证两种灵动岛宽度都放得下
                Text(context.state.shortText)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(WidgetTheme.accent)
            } minimal: {
                Image(systemName: "person.fill")
                    .foregroundStyle(WidgetTheme.accent)
            }
            .widgetURL(URL(string: "guiwei://items"))
            .keylineTint(WidgetTheme.accent)
        }
    }
}

/// 锁定屏 / 通知中心上的样式
private struct LockScreenCard: View {
    let context: ActivityViewContext<GuiWeiActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(WidgetTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.itemName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("借给 \(context.attributes.borrower)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(context.state.statusText)
                }
                .font(.caption)
                .foregroundStyle(context.state.isReturned ? .green : WidgetTheme.accent)

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("放回：\(context.attributes.locationPath)")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
