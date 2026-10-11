import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 「下一件要做的事」的实时活动界面。
///
/// 只展示一件事：最该处理的那件东西。到期优先，其次归还。
///
/// **灵动岛的宽度适配**（iPhone 17 Pro 与 18 Pro 的灵动岛宽度不同）：
/// 1. 紧凑态与最简态只放「一个图标 + 最多三个字」，任何机型都不会被裁切；
/// 2. 展开态里较长的内容用 `.dynamicIsland(verticalPlacement: .belowIfTooWide)`，
///    灵动岛不够宽时系统会自动把它落到下方一行，而不是硬挤；
/// 3. 需要完整信息的场景交给锁定屏，那里宽度不受灵动岛限制。
struct GuiWeiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuiWeiActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(WidgetTheme.cardBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = WidgetTheme.accent(for: context.attributes.kind,
                                            daysLeft: context.state.daysLeft)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: context.attributes.symbolName)
                            .font(.caption2)
                        Text(context.attributes.kind == .expiry ? "要到期" : "该还了")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(accent)
                    .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.shortText)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                        .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBody(context: context, accent: accent)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
            } compactLeading: {
                // **规则 2：紧凑区要让人一眼看出是什么东西**，不能只放图标或时间。
                // 这里放物品名的前两个字（灵动岛两侧各只有约 40pt，两个汉字刚好）。
                Text(shortName(context.attributes.title))
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } compactTrailing: {
                // 只放「3天」「逾期」这类短文案，两种灵动岛宽度都放得下
                Text(context.state.shortText)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(accent)
            } minimal: {
                // 最简态只够放一个字
                Text(shortName(context.attributes.title).prefix(1))
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(accent)
            }
            // 刻意不设 .widgetURL：它会和「知道了」按钮抢点击区域。
            .keylineTint(accent)
        }
    }
}

/// 物品名的紧凑写法：最多两个汉字，超长截断。
/// 目的：让灵动岛上一眼能看出"是什么东西"，而不是只有一个时间和图标。
private func shortName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 2 { return trimmed }
    return String(trimmed.prefix(2))
}

// MARK: - 展开态主体

private struct ExpandedBody: View {
    let context: ActivityViewContext<GuiWeiActivityAttributes>
    let accent: Color

    private var isExpiry: Bool { context.attributes.kind == .expiry }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 物品名 + 还剩多久
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let due = context.state.dueDate {
                    // 用相对时间格式化，系统自动刷新，不必等 App 唤醒
                    Text(due, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }

            // 到期 → 放在哪；归还 → 借给谁
            Text(isExpiry ? context.attributes.subtitle
                          : "借给 \(context.attributes.subtitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // 时间进度条
            CapsuleBar(progress: context.state.progress, tint: accent)
                .padding(.top, 1)

            HStack(spacing: 5) {
                Image(systemName: isExpiry ? "mappin.and.ellipse" : "arrow.uturn.backward")
                    .font(.system(size: 9))
                Text(footnote)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 10)
                // 收起入口。做成"右侧独立小按钮 + × 图标"：
                // 位置离正文远、尺寸收敛，既点得到，也不容易在滑动时误触。
                Button(intent: DismissIslandIntent()) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("收起")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.18), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: String {
        if isExpiry {
            return context.state.pendingCount > 1
                ? "另有 \(context.state.pendingCount - 1) 件要到期"
                : "放在 \(context.attributes.subtitle)"
        }
        let place = context.attributes.locationPath
        let base = place.isEmpty ? "记得要回来" : "归还后放回 \(place)"
        return context.state.pendingCount > 1
            ? "\(base) · 另有 \(context.state.pendingCount - 1) 件"
            : base
    }
}

/// 细胶囊进度条。widget 里比 ProgressView 更可控。
private struct CapsuleBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * min(max(progress, 0), 1), 4))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - 锁定屏 / 通知中心

private struct LockScreenCard: View {
    let context: ActivityViewContext<GuiWeiActivityAttributes>

    private var accent: Color {
        WidgetTheme.accent(for: context.attributes.kind, daysLeft: context.state.daysLeft)
    }
    private var isExpiry: Bool { context.attributes.kind == .expiry }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 42, height: 42)
                Image(systemName: context.attributes.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isExpiry ? "要到期" : "该还了")
                        .font(.caption2)
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    Text(context.state.shortText)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                }

                Text(context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(isExpiry ? context.attributes.subtitle
                              : "借给 \(context.attributes.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                CapsuleBar(progress: context.state.progress, tint: accent)
                    .padding(.vertical, 2)

                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text(context.state.statusText)
                    if let due = context.state.dueDate {
                        Text("·")
                        Text(due, style: .relative)
                    }
                }
                .font(.caption2)
                .foregroundStyle(accent)

                HStack(spacing: 8) {
                    if !isExpiry, !context.attributes.locationPath.isEmpty {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 9))
                        Text("放回：\(context.attributes.locationPath)").lineLimit(1)
                        Spacer(minLength: 6)
                    } else {
                        Spacer(minLength: 0)
                    }
                    // 锁定屏上也能直接收起，不用打开 App
                    Button(intent: DismissIslandIntent()) {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("收起")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - 收起灵动岛

/// 长按灵动岛后点「知道了」即可收起，不必打开 App。
///
/// **必须是 `LiveActivityIntent` 而不是普通 `AppIntent`**：
/// 前者由系统在 App 的进程里执行，能正确访问到这个 App 的实时活动。
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
