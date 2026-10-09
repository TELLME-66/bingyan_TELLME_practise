import SwiftUI
import SwiftData

/// 新建／编辑位置。
struct SpotEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \StorageSpot.name) private var allSpots: [StorageSpot]

    let spot: StorageSpot?

    @State private var name = ""
    @State private var kind: SpotKind = .container
    @State private var parent: StorageSpot?
    @State private var colorHex = "2E5FA3"
    @State private var note = ""

    @State private var loaded = false

    private let palette = ["2E5FA3", "4B5BD2", "2E8FA3", "3FA36B", "E08A2E", "D2564B", "8A5BD2", "6B7280"]

    private var isEditing: Bool { spot != nil }

    /// 选父级时不能选到自己或自己的子孙，否则会形成环
    private var parentOptions: [StorageSpot] {
        allSpots
            .filter { candidate in
                guard let spot else { return true }
                return candidate.persistentModelID != spot.persistentModelID
                    && !isDescendant(candidate, of: spot)
            }
            .sorted { $0.fullPath < $1.fullPath }
    }

    private func isDescendant(_ candidate: StorageSpot, of ancestor: StorageSpot) -> Bool {
        var node = candidate.parent
        var guardCount = 0
        while let current = node, guardCount < 8 {
            if current.persistentModelID == ancestor.persistentModelID { return true }
            node = current.parent
            guardCount += 1
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称，例如「第二层抽屉」", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(SpotKind.allCases) { k in
                            Label(k.label, systemImage: k.symbolName).tag(k)
                        }
                    }
                    Picker("上级位置", selection: $parent) {
                        Text("无（顶层）").tag(StorageSpot?.none)
                        ForEach(parentOptions) { option in
                            Text(option.fullPath).tag(Optional(option))
                        }
                    }
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.gapM) {
                        ForEach(palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(height: 28)
                                .overlay {
                                    if hex == colorHex {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, Theme.gapXS)
                }

                Section {
                    Label("敬请期待实体标签", systemImage: "tag")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("实体标签")
                } footer: {
                    Text("Apple 未向第三方 App 开放 AirTag 等实体标签的接口，功能上线后会在这里开放绑定。")
                }

                Section("备注") {
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "编辑位置" : "新建位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let spot else { return }
        name = spot.name
        kind = spot.kind
        parent = spot.parent
        colorHex = spot.colorHex
        note = spot.note ?? ""
    }

    private func save() {
        let target: StorageSpot
        if let spot {
            target = spot
        } else {
            target = StorageSpot(name: name)
            context.insert(target)
        }

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kindRaw = kind.rawValue
        target.parent = parent
        target.colorHex = colorHex
        target.note = note.isEmpty ? nil : note

        try? context.save()
        dismiss()
    }
}
