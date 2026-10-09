import SwiftUI

/// 列表里的一行。信息优先级：图片 → 名称 → 位置 → 状态角标。
struct ItemRowView: View {
    let item: Item

    var body: some View {
        HStack(spacing: Theme.gapM) {
            ItemThumbnail(item: item)

            VStack(alignment: .leading, spacing: Theme.gapXS) {
                HStack(spacing: Theme.gapXS) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: Theme.gapXS) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                    Text(item.locationPath)
                        .font(.footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: Theme.gapXS) {
                    if item.quantity > 1 {
                        TagChip(text: "×\(item.quantity)")
                    }
                    ExpiryBadge(item: item, compact: true)
                    if let loan = item.activeLoan {
                        LoanBadge(loan: loan, compact: true)
                    }                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.gapXS)
    }
}
