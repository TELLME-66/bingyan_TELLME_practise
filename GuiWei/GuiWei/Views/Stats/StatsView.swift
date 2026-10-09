import SwiftUI
import SwiftData
import Charts

/// 统计页：把"我到底有多少东西、都堆在哪、什么快过期了"讲清楚。
/// 对应题目进阶要求里的"更丰富的统计功能"。
struct StatsView: View {
    @Query private var items: [Item]
    @Query private var spots: [StorageSpot]
    @Query(sort: \ItemCategory.sortIndex) private var categories: [ItemCategory]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gapXL) {
                    tiles
                    expiryChart
                    categoryChart
                    spotChart
                }
                .padding(Theme.gapL)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
        }
    }

    // MARK: - 概览

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.gapM) {
            StatTile(title: "物品种类", value: "\(items.count)", symbol: "shippingbox")
            StatTile(title: "物品总数", value: "\(items.reduce(0) { $0 + $1.quantity })",
                     symbol: "number", tint: .blue)
            StatTile(title: "临期或过期", value: "\(expiringItems.count)",
                     symbol: "clock.badge.exclamationmark",
                     tint: expiringItems.isEmpty ? .green : .orange)
            StatTile(title: "借出在外", value: "\(lentItems.count)",
                     symbol: "person.2", tint: lentItems.isEmpty ? .green : .purple)
        }
    }

    // MARK: - 到期分布

    private var expiringItems: [Item] {
        items.filter { $0.expiryState == .soon || $0.expiryState == .expired }
    }

    private var lentItems: [Item] {
        items.filter(\.isLentOut)
    }

    private struct ExpiryDatum: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private var expiryData: [ExpiryDatum] {
        let expired = items.filter { $0.expiryState == .expired }.count
        let soon = items.filter { $0.expiryState == .soon }.count
        let safe = items.filter { $0.expiryState == .safe }.count
        let none = items.filter { $0.expiryState == .none }.count
        return [
            ExpiryDatum(label: "已过期", count: expired, color: .red),
            ExpiryDatum(label: "30 天内", count: soon, color: .orange),
            ExpiryDatum(label: "正常", count: safe, color: .green),
            ExpiryDatum(label: "无期限", count: none, color: .gray)
        ].filter { $0.count > 0 }
    }

    private var expiryChart: some View {
        SectionCard(title: "到期情况") {
            if expiryData.isEmpty {
                emptyHint("还没有设置到期时间的物品")
            } else {
                HStack(alignment: .center, spacing: Theme.gapL) {
                    Chart(expiryData) { datum in
                        SectorMark(angle: .value("数量", datum.count),
                                   innerRadius: .ratio(0.62),
                                   angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(datum.color)
                    }
                    .frame(width: 140, height: 140)

                    VStack(alignment: .leading, spacing: Theme.gapS) {
                        ForEach(expiryData) { datum in
                            HStack(spacing: Theme.gapS) {
                                Circle().fill(datum.color).frame(width: 8, height: 8)
                                Text(datum.label).font(.footnote)
                                Spacer()
                                Text("\(datum.count)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 分类分布

    private struct CategoryDatum: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
        let color: Color
    }

    private var categoryData: [CategoryDatum] {
        categories.compactMap { category in
            guard !category.items.isEmpty else { return nil }
            return CategoryDatum(name: category.name,
                                 count: category.totalQuantity,
                                 color: Color(hex: category.colorHex))
        }.sorted { $0.count > $1.count }
    }

    private var categoryChart: some View {
        SectionCard(title: "分类分布（按数量）") {
            if categoryData.isEmpty {
                emptyHint("还没有物品")
            } else {
                Chart(categoryData) { datum in
                    BarMark(x: .value("数量", datum.count),
                            y: .value("分类", datum.name))
                        .foregroundStyle(datum.color)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(datum.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(categoryData.count) * 34 + 20)
            }
        }
    }

    // MARK: - 位置分布

    private struct SpotDatum: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
    }

    /// 只统计顶层房间，避免把三层结构全铺开
    private var spotData: [SpotDatum] {
        spots.filter { $0.parent == nil }
            .map { SpotDatum(name: $0.name, count: $0.totalQuantity) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    private var spotChart: some View {
        SectionCard(title: "东西都在哪个房间") {
            if spotData.isEmpty {
                emptyHint("还没有归位的物品")
            } else {
                Chart(spotData) { datum in
                    BarMark(x: .value("房间", datum.name),
                            y: .value("数量", datum.count))
                        .foregroundStyle(Color(hex: "2E5FA3"))
                        .cornerRadius(4)
                }
                .frame(height: 180)
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
