import SwiftUI
import UIKit
import SwiftData
import PhotosUI

/// 新增／编辑物品。新增和编辑共用一套表单，靠 `item == nil` 区分模式。
struct ItemEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ItemCategory.sortIndex) private var categories: [ItemCategory]
    @Query(sort: \StorageSpot.name) private var spots: [StorageSpot]

    /// nil 表示新建
    let item: Item?

    @State private var name = ""
    @State private var quantity = 1
    @State private var selectedCategory: ItemCategory?
    @State private var selectedSpot: StorageSpot?
    @State private var hasExpiry = false
    @State private var expireDate = Date.now.addingTimeInterval(86400 * 30)
    @State private var tagsText = ""
    @State private var note = ""

    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var removeExistingImage = false

    @State private var loaded = false

    private var isEditing: Bool { item != nil }
    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                basicSection
                locationSection
                expirySection
                trackingSection
                noteSection
            }
            .navigationTitle(isEditing ? "编辑物品" : "添加物品")
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
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                        removeExistingImage = false
                    }
                }
            }
            // 相册：用 .photosPicker 修饰符弹出系统相册选择器。
            // 注意不要用 PhotosPicker 控件直接塞进 Form 行里——一行里放多个可点控件时，
            // Form 会把整行当成一个按钮，点击会被相机那个按钮抢走。
            .photosPicker(isPresented: $showingLibrary,
                          selection: $photoItem,
                          matching: .images,
                          photoLibrary: .shared())
            // 相机：全屏呈现，和相册选择器用两套不同的呈现方式，互不干扰
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    pickedImage = image
                    removeExistingImage = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 分块

    private var currentDisplayImage: UIImage? {
        if removeExistingImage { return nil }
        if let pickedImage { return pickedImage }
        if let data = item?.imageData { return UIImage(data: data) }
        return nil
    }

    private var photoSection: some View {
        // 关键：每个可点动作独占一个 Form 行。
        // 一行里只放一个控件，点击目标才明确，不会被相邻控件抢走。
        Section {
            previewRow

            Button {
                showingLibrary = true
            } label: {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }

            if cameraAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label("拍照", systemImage: "camera")
                }
            }

            if currentDisplayImage != nil {
                Button(role: .destructive) {
                    pickedImage = nil
                    photoItem = nil
                    removeExistingImage = true
                } label: {
                    Label("移除照片", systemImage: "trash")
                }
            }
        } header: {
            Text("照片")
        } footer: {
            Text("保存时会自动压缩：原图存到数据库外部，列表只用缩略图。")
        }
    }

    /// 预览行本身不可点，只负责显示当前选中的图片
    private var previewRow: some View {
        HStack(spacing: Theme.gapM) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .fill(Color(.tertiarySystemFill))
                if let image = currentDisplayImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: Theme.gapXS) {
                Text(currentDisplayImage == nil ? "还没有照片" : "已选择照片")
                    .font(.subheadline)
                Text(currentDisplayImage == nil
                     ? "可以从相册选一张，也可以直接拍一张。"
                     : "保存时会把原图压缩后存起来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.gapXS)
    }

    private var basicSection: some View {
        Section("基本信息") {
            TextField("名称", text: $name)

            Picker("分类", selection: $selectedCategory) {
                Text("未分类").tag(ItemCategory?.none)
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.symbolName)
                        .tag(Optional(category))
                }
            }

            Stepper("数量 \(quantity)", value: $quantity, in: 1...999)
        }
    }

    private var locationSection: some View {
        Section {
            Picker("存放位置", selection: $selectedSpot) {
                Text("未归位").tag(StorageSpot?.none)
                ForEach(spots.sorted(by: { $0.fullPath < $1.fullPath })) { spot in
                    Text(spot.fullPath).tag(Optional(spot))
                }
            }
        } header: {
            Text("位置")
        } footer: {
            Text("位置按「房间 › 容器 › 格位」三层组织，先在「位置」页里建好，这里就能选到。")
        }
    }

    private var expirySection: some View {
        Section("到期") {
            Toggle("设置到期时间", isOn: $hasExpiry.animation())
            if hasExpiry {
                DatePicker("到期日期", selection: $expireDate, displayedComponents: .date)
            }
        }
    }

    /// 实体标签占位：不提供编辑，只告诉用户后续会开放
    private var trackingSection: some View {
        Section {
            Label("敬请期待实体标签", systemImage: "tag")
                .foregroundStyle(.secondary)
        } header: {
            Text("实体标签")
        } footer: {
            Text("Apple 未向第三方 App 开放 AirTag 等实体标签的接口，功能上线后会在这里开放绑定。")
        }
    }

    private var noteSection: some View {
        Section("标签与备注") {
            TextField("标签，用逗号分隔", text: $tagsText)
            TextField("备注", text: $note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    // MARK: - 数据读写

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true

        #if DEBUG
        // 调试入口：模拟器里没有鼠标可点，靠启动参数直接把相册／相机弹出来验证。
        // 只在 Debug 构建里存在，Release 不受影响。
        // 用法：xcrun simctl launch booted com.bingyan.guiwei -startNew 1 -openLibrary 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if UserDefaults.standard.bool(forKey: "openLibrary") { showingLibrary = true }
            if UserDefaults.standard.bool(forKey: "openCamera") { showingCamera = true }
        }
        #endif

        guard let item else {
            hasExpiry = false
            return
        }
        name = item.name
        quantity = item.quantity
        selectedCategory = item.category
        selectedSpot = item.spot
        if let date = item.expireDate {
            hasExpiry = true
            expireDate = date
        }
        tagsText = item.tags.joined(separator: "，")
        note = item.note ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let target: Item
        if let item {
            target = item
        } else {
            target = Item(name: trimmedName)
            context.insert(target)
        }

        target.name = trimmedName
        target.quantity = quantity
        target.category = selectedCategory
        target.spot = selectedSpot
        target.expireDate = hasExpiry ? expireDate : nil
        target.note = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
        target.tags = tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 图片：原图走 externalStorage，缩略图内联，列表滚动不需要解码大图
        if let pickedImage {
            target.imageData = ImagePipeline.imageData(from: pickedImage)
            target.thumbnailData = ImagePipeline.thumbnailData(from: pickedImage)
        } else if removeExistingImage {
            target.imageData = nil
            target.thumbnailData = nil
        }

        target.touch()
        try? context.save()

        // 保存后同步生态：通知重排 + Spotlight 重建
        Task { @MainActor in
            if hasExpiry {
                await NotificationService.shared.scheduleExpiry(for: target)
            } else {
                NotificationService.shared.cancelExpiry(for: target)
            }
            let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
            SpotlightIndexer.reindex(items: all)
            WidgetBridge.publish(items: all)
        }

        dismiss()
    }
}
