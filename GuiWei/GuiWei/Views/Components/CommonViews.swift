import SwiftUI
import UIKit

// MARK: - 临期角标

/// 剩余天数的角标。颜色跟随 ExpiryState，取值来自 Theme。
struct ExpiryBadge: View {
    let item: Item
    var compact: Bool = false

    var body: some View {
        if let text = item.expiryText, item.expiryState != .none {
            let color = Theme.color(for: item.expiryState)
            Text(text)
                .font(compact ? .caption2 : .caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, Theme.gapS)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - 通用小标签

struct TagChip: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.gapS)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - 借出状态角标

struct LoanBadge: View {
    let loan: LoanRecord
    var compact: Bool = false

    var body: some View {
        let color = Theme.color(for: loan.dueState)
        HStack(spacing: Theme.gapXS) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Text(compact ? "借出中" : "借给 \(loan.borrower)")
                .font(compact ? .caption2 : .caption)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.gapS)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - 详情页的一行信息

struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String
    var valueColor: Color = .primary
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: Theme.gapS) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.gapS)
                Text(value)
                    .font(.body)
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - 卡片容器

/// 统一的分组卡片：圆角、内边距、背景色都从这里出，避免每个界面各写一套。
struct SectionCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapM) {
            if let title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(Theme.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

// MARK: - 统计页的小数字块

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = Color(hex: "2E5FA3")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapS) {
            HStack(spacing: Theme.gapXS) {
                Image(systemName: symbol)
                    .font(.footnote)
                Text(title)
                    .font(.footnote)
            }
            .foregroundStyle(tint)

            Text(value)
                .numberFont(.title2)
                .foregroundStyle(.primary)
        }
        .padding(Theme.gapM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - 物品缩略图

/// 列表里的 56×56 缩略图。没有图片时给一个按分类着色的占位块，避免出现空洞。
struct ItemThumbnail: View {
    let item: Item
    var size: CGFloat = Theme.thumbSize

    var body: some View {
        Group {
            if let image = ImagePipeline.ThumbnailCache.shared.image(uid: item.uid, data: item.thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(hex: item.category?.colorHex ?? "9AA1AC").opacity(0.15)
                    Image(systemName: item.category?.symbolName ?? "shippingbox")
                        .font(.system(size: size * 0.34))
                        .foregroundStyle(Color(hex: item.category?.colorHex ?? "9AA1AC"))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - 位置图标

struct SpotIcon: View {
    let spot: StorageSpot
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(Color(hex: spot.colorHex).opacity(0.15))
            Image(systemName: spot.kind.symbolName)
                .font(.system(size: size * 0.45))
                .foregroundStyle(Color(hex: spot.colorHex))
        }
        .frame(width: size, height: size)
    }
}
