import SwiftUI
import UIKit

/// 分享卡片：把一件物品渲染成一张适合发到群里的图。
/// 用 ImageRenderer 渲染，因此这里只描述"长什么样"，不关心导出。
struct ShareCardView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapL) {
            HStack(spacing: Theme.gapS) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.white)
                Text("归位")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(alignment: .top, spacing: Theme.gapL) {
                if let data = item.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .fill(Color.white.opacity(0.15))
                        Image(systemName: item.category?.symbolName ?? "shippingbox")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 140, height: 140)
                }

                VStack(alignment: .leading, spacing: Theme.gapS) {
                    Text(item.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Label(item.locationPath, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))

                    if let expiry = item.expiryText {
                        Label(expiry, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    if let loan = item.activeLoan {
                        Label("借给 \(loan.borrower)", systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer(minLength: 0)

                    Text(item.category?.name ?? "未分类")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.gapS)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(Color.white.opacity(0.3))

            HStack {
                Text("记录于 \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("guiwei://item/\(item.uid.prefix(8))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(Theme.gapXL)
        .frame(width: 600, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "1B366B"), Color(hex: "1C7A8C")],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
    }
}
