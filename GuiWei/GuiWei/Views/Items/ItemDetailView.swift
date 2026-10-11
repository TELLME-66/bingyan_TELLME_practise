import SwiftUI
import UIKit
import SwiftData

/// 物品详情。把列表放不下的字段全收在这里，并提供后续动作（编辑、借出、分享、跳「查找」）。
struct ItemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    let item: Item

    @State private var showingEditor = false
    @State private var showingLendSheet = false
    @State private var showingDeleteConfirm = false
    @State private var shareImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gapXL) {
                hero
                header
                infoCard
                trackingCard
                if item.activeLoan != nil || loanHistory.isEmpty == false { loanCard }
                if let note = item.note, !note.isEmpty { noteCard(note) }
            }
            .padding(.horizontal, Theme.gapL)
            .padding(.bottom, Theme.gapXL)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditor) {
            ItemEditorView(item: item)
                .appSheetRadius()
        }
        .sheet(isPresented: $showingLendSheet) {
            LendSheet(item: item)
                .appSheetRadius()
        }
        .alert("删除这件物品？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { deleteItem() }
        } message: {
            Text("「\(item.name)」的记录会被移除，无法恢复。")
        }
        .task {
            shareImage = makeShareImage()
        }
    }

    // MARK: - 分块

    @ViewBuilder
    private var hero: some View {
        if let data = item.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: Theme.heroHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
                .padding(.top, Theme.gapS)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.gapS) {
            Text(item.name)
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: Theme.gapS) {
                TagChip(text: item.category?.name ?? "未分类",
                        color: Color(hex: item.category?.colorHex ?? "9AA1AC"))
                ExpiryBadge(item: item)
                if let loan = item.activeLoan { LoanBadge(loan: loan) }
            }

            if !item.tags.isEmpty {
                HStack(spacing: Theme.gapS) {
                    ForEach(item.tags, id: \.self) { tag in
                        TagChip(text: "#\(tag)")
                    }
                }
            }
        }
    }

    private var infoCard: some View {
        SectionCard(title: "物品信息") {
            VStack(spacing: 0) {
                InfoRow(symbol: "mappin.and.ellipse", title: "存放位置", value: item.locationPath)
                Divider()
                InfoRow(symbol: "square.grid.2x2", title: "分类",
                        value: item.category?.name ?? "未分类",
                        valueColor: Color(hex: item.category?.colorHex ?? "9AA1AC"))
                Divider()
                InfoRow(symbol: "number", title: "数量", value: "\(item.quantity)")
                Divider()
                InfoRow(symbol: "calendar", title: "到期时间",
                        value: item.expireDate?.formatted(date: .abbreviated, time: .omitted) ?? "未设置",
                        valueColor: item.expireDate == nil ? .secondary : Theme.color(for: item.expiryState))
                Divider()
                InfoRow(symbol: "clock", title: "最近更新",
                        value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    /// 实体标签占位。Apple 未向第三方 App 开放 AirTag 接口，
    /// 所以这里保留入口并明确告知用户，而不是做一个用不了的功能。
    private var trackingCard: some View {
        SectionCard(title: "实体标签") {
            HStack(spacing: Theme.gapS) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                Text("敬请期待实体标签")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loanHistory: [LoanRecord] {
        item.loans.sorted { $0.lentAt > $1.lentAt }
    }

    private var loanCard: some View {
        SectionCard(title: "借出记录") {
            VStack(spacing: 0) {
                ForEach(loanHistory) { loan in
                    HStack(spacing: Theme.gapM) {
                        Image(systemName: loan.isActive ? "person.fill" : "checkmark.circle")
                            .foregroundStyle(Theme.color(for: loan.dueState))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loan.borrower).font(.body)
                            Text(loanText(loan))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(loan.statusText)
                            .font(.caption)
                            .foregroundStyle(Theme.color(for: loan.dueState))
                    }
                    .padding(.vertical, 10)
                    if loan.id != loanHistory.last?.id { Divider() }
                }
            }
        }
    }

    private func loanText(_ loan: LoanRecord) -> String {
        var parts = ["借出于 \(loan.lentAt.friendlyDay)"]
        if let due = loan.dueAt { parts.append("应还 \(due.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }

    private func noteCard(_ note: String) -> some View {
        SectionCard(title: "备注") {
            Text(note)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingEditor = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }

                Button {
                    toggleFavorite()
                } label: {
                    Label(item.isFavorite ? "取消收藏" : "收藏",
                          systemImage: item.isFavorite ? "star.slash" : "star")
                }

                if item.isLentOut {
                    Button {
                        returnItem()
                    } label: {
                        Label("标记已归还", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        showingLendSheet = true
                    } label: {
                        Label("借出给别人", systemImage: "person.badge.plus")
                    }
                }

                if let shareImage {
                    ShareLink(item: Image(uiImage: shareImage),
                              preview: SharePreview(item.name, image: Image(uiImage: shareImage))) {
                        Label("分享物品卡片", systemImage: "square.and.arrow.up")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - 操作

    private func toggleFavorite() {
        item.isFavorite.toggle()
        item.touch()
        try? context.save()
        shareImage = makeShareImage()
    }

    private func returnItem() {
        guard let loan = item.activeLoan else { return }
        loan.returnedAt = .now
        item.touch()
        try? context.save()
        NotificationService.shared.cancelLoan(for: item.uid)
        LiveActivityCenter.shared.refreshFromStore()
    }

    private func deleteItem() {
        NotificationService.shared.cancelExpiry(for: item)
        NotificationService.shared.cancelLoan(for: item.uid)
        context.delete(item)
        try? context.save()
        dismiss()
    }

    /// 用 ImageRenderer 把 ShareCardView 渲染成图片，再交给系统分享面板。
    /// 这是把 SwiftUI 界面变成可分享图片的标准做法。
    @MainActor
    private func makeShareImage() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(item: item))
        renderer.scale = 2
        return renderer.uiImage
    }
}
