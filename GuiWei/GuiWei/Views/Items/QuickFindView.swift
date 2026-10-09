import SwiftUI
import SwiftData

/// 「东西放哪了」——本 App 的招牌功能。
/// 输入名字，直接告诉你它在哪个房间的哪个格子里；
/// 如果借出去了，就直接告诉你借给谁了。这也是 Siri 快捷指令回答的同一套逻辑。
struct QuickFindView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Item.name) private var items: [Item]

    /// 允许从深链或快捷指令带一个初始关键词进来
    var initialQuery: String = ""

    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [Item] {
        guard !trimmed.isEmpty else { return [] }
        return items.filter { item in
            item.name.localizedStandardContains(trimmed)
                || item.tags.contains { $0.localizedStandardContains(trimmed) }
                || item.locationPath.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                result
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("找东西")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                if !initialQuery.isEmpty { query = initialQuery }
                focused = initialQuery.isEmpty
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.gapS) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("例如：护照、充电器、工具箱", text: $query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.gapM)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .padding(Theme.gapL)
    }

    @ViewBuilder
    private var result: some View {
        if trimmed.isEmpty {
            hint
        } else if matches.isEmpty {
            ContentUnavailableView {
                Label("没找到「\(trimmed)」", systemImage: "questionmark.circle")
            } description: {
                Text("换个说法试试，比如只输入名字里的两个字。也可以直接说「归位 我的护照放哪了」。")
            }
        } else {
            List {
                if let best = matches.first {
                    Section {
                        answerCard(for: best)
                            .listRowInsets(EdgeInsets(top: Theme.gapS, leading: Theme.gapL,
                                                      bottom: Theme.gapS, trailing: Theme.gapL))
                            .listRowBackground(Color.clear)
                    }
                }
                if matches.count > 1 {
                    Section("其它可能的物品") {
                        ForEach(matches.dropFirst()) { item in
                            HStack(spacing: Theme.gapM) {
                                ItemThumbnail(item: item, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.body)
                                    Text(item.locationPath)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.isLentOut { LoanBadge(loan: item.activeLoan!, compact: true) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var hint: some View {
        VStack(spacing: Theme.gapL) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("输入物品的名字、标签或位置")
                .font(.headline)
            Text("找不到东西的时候，先问「归位」。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Theme.gapS) {
                Label("支持按标签搜，例如「重要」", systemImage: "tag")
                Label("支持按位置搜，例如「衣柜」", systemImage: "mappin.and.ellipse")
                Label("借出去的会告诉你在谁手里", systemImage: "person.fill")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, Theme.gapS)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.gapXL)
    }

    /// 一句话答案 + 完整路径，这是整个 App 最重要的一块界面
    private func answerCard(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: Theme.gapM) {
            HStack(spacing: Theme.gapS) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "2E5FA3"))
                Text(item.isLentOut ? "不在原位" : "它在这里")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(item.locationPath)
                .font(.title3)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)

            if let loan = item.activeLoan {
                Label("已借给 \(loan.borrower) · \(loan.statusText)", systemImage: "person.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.color(for: loan.dueState))
            }

            HStack(spacing: Theme.gapS) {
                TagChip(text: item.category?.name ?? "未分类",
                        color: Color(hex: item.category?.colorHex ?? "9AA1AC"))
                ExpiryBadge(item: item)            }

            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}
