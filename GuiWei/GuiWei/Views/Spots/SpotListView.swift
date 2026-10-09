import SwiftUI
import SwiftData

/// 位置列表：房间 → 容器 → 格位的层级入口。
/// 这是「归位」区别于普通清单 App 的地方——物品不是散着的，而是有物理坐标的。
struct SpotListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StorageSpot.name) private var spots: [StorageSpot]

    @State private var showingEditor = false
    @State private var editingSpot: StorageSpot?

    private var roots: [StorageSpot] {
        spots.filter { $0.parent == nil }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty {
                    ContentUnavailableView {
                        Label("还没有建立位置", systemImage: "square.grid.3x3")
                    } description: {
                        Text("先建一个「卧室」，再往里加「衣柜」「第二层抽屉」，物品就能放到具体格位了。")
                    } actions: {
                        Button("新建位置") { showingEditor = true }
                            .buttonStyle(.borderedProminent)
                            .appButtonShape()
                    }
                } else {
                    List {
                        ForEach(roots) { spot in
                            Section {
                                spotRows(for: spot)
                            } header: {
                                Text(spot.name)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("位置")
            .navigationDestination(for: StorageSpot.self) { SpotDetailView(spot: $0) }
            .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: {
                        Label("新建位置", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                SpotEditorView(spot: nil)
                    .appSheetRadius()
            }
            .sheet(item: $editingSpot) { spot in
                SpotEditorView(spot: spot)
                    .appSheetRadius()
            }
        }
    }

    /// 递归展开一个房间下面的所有容器与格位，缩进表示层级
    @ViewBuilder
    private func spotRows(for spot: StorageSpot) -> some View {
        NavigationLink(value: spot) {
            SpotRowView(spot: spot, depth: 0)
        }
        .listRowBackground(Color(.secondarySystemGroupedBackground))

        ForEach(children(of: spot)) { child in
            NavigationLink(value: child) {
                SpotRowView(spot: child, depth: 1)
            }
            .listRowBackground(Color(.secondarySystemGroupedBackground))

            ForEach(children(of: child)) { grand in
                NavigationLink(value: grand) {
                    SpotRowView(spot: grand, depth: 2)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        }
    }

    private func children(of spot: StorageSpot) -> [StorageSpot] {
        spot.children.sorted { $0.name < $1.name }
    }
}

/// 位置行：图标、名称、物品数量
struct SpotRowView: View {
    let spot: StorageSpot
    var depth: Int = 0

    var body: some View {
        HStack(spacing: Theme.gapM) {
            SpotIcon(spot: spot, size: 36)
                .padding(.leading, CGFloat(depth) * Theme.gapL)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.gapXS) {
                    Text(spot.name).font(.body)
                }
                Text("\(spot.kind.label) · \(spot.totalItemCount) 件物品")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if spot.totalQuantity > 0 {
                Text("×\(spot.totalQuantity)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
