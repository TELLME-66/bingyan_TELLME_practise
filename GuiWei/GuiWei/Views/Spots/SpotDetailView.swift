import SwiftUI
import SwiftData

/// 位置详情：这个格子里放了什么、属于哪个房间。
struct SpotDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let spot: StorageSpot

    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false

    private var childSpots: [StorageSpot] {
        spot.children.sorted { $0.name < $1.name }
    }

    private var directItems: [Item] {
        spot.items.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            headerSection

            trackingSection

            if !childSpots.isEmpty {
                Section("下级位置") {
                    ForEach(childSpots) { child in
                        NavigationLink(value: child) {
                            SpotRowView(spot: child, depth: 0)
                        }
                    }
                }
            }

            Section("放在这里的物品（\(directItems.count)）") {
                if directItems.isEmpty {
                    Text("这一层还没有直接放物品。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(directItems) { item in
                        NavigationLink(value: item) {
                            ItemRowView(item: item)
                        }
                    }
                }
            }

            if let note = spot.note, !note.isEmpty {
                Section("备注") { Text(note) }
            }

            Section {
                Button {
                    showingEditor = true
                } label: {
                    Label("编辑这个位置", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("删除这个位置", systemImage: "trash")
                }
            } footer: {
                Text("删除位置不会删除物品，物品会变成「未归位」，可以再重新指定。")
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
        .navigationDestination(for: StorageSpot.self) { SpotDetailView(spot: $0) }
        .sheet(isPresented: $showingEditor) {
            SpotEditorView(spot: spot)
                .appSheetRadius()
        }
        .alert("删除这个位置？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { deleteSpot() }
        } message: {
            Text("「\(spot.fullPath)」下的物品会变成未归位。")
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.gapS) {
                HStack(spacing: Theme.gapM) {
                    SpotIcon(spot: spot, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.name).font(.headline)
                        Text(spot.kind.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Label(spot.fullPath, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: Theme.gapS) {
                    TagChip(text: "\(spot.totalItemCount) 件物品")
                    TagChip(text: "共 \(spot.totalQuantity) 个")
                }
            }
            .padding(.vertical, Theme.gapXS)
        }
    }

    /// 实体标签占位
    private var trackingSection: some View {
        Section("实体标签") {
            HStack(spacing: Theme.gapS) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                Text("敬请期待实体标签")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Theme.gapXS)
        }
    }

    private func deleteSpot() {
        // 先把子位置和物品解绑，避免级联删除误伤物品
        for item in spot.items { item.spot = nil }
        for child in spot.children { child.parent = spot.parent }
        context.delete(spot)
        try? context.save()
        dismiss()
    }
}
