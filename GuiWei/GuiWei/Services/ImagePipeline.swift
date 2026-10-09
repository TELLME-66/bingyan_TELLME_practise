import UIKit

/// 图片处理管线。
///
/// 为什么需要它：直接把相册原图（动辄 3~8 MB）塞进数据库，
/// 一百条物品就能把 .store 撑到几百 MB，列表滚动也会卡。
/// 所以写入时分两路：
/// - 原图：等比缩到最长边 1600、JPEG 质量 0.7，交给 @Attribute(.externalStorage)
/// - 缩略图：最长边 300、质量 0.6，直接内联存储，列表滚动时不解码大图
enum ImagePipeline {
    static let maxOriginalDimension: CGFloat = 1600
    static let maxThumbnailDimension: CGFloat = 300

    static func imageData(from image: UIImage) -> Data? {
        resized(image, maxDimension: maxOriginalDimension)
            .jpegData(compressionQuality: 0.7)
    }

    static func thumbnailData(from image: UIImage) -> Data? {
        resized(image, maxDimension: maxThumbnailDimension)
            .jpegData(compressionQuality: 0.6)
    }

    /// 缩略图解码缓存。
    ///
    /// 列表滚动时 SwiftUI 会反复求值 body，如果每次都 `UIImage(data:)` 解码，
    /// 真机上会明显掉帧（这是实机测试发现的性能问题）。
    /// NSCache 本身线程安全，且在内存吃紧时会自动回收，适合这里。
    final class ThumbnailCache: @unchecked Sendable {
        static let shared = ThumbnailCache()
        private let cache = NSCache<NSString, UIImage>()

        private init() { cache.countLimit = 300 }

        func image(uid: String, data: Data?) -> UIImage? {
            guard let data else { return nil }
            // 用 uid + 数据长度做键：图片被替换时长度基本一定变化，缓存自然失效
            let key = "\(uid)#\(data.count)" as NSString
            if let hit = cache.object(forKey: key) { return hit }
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        }
    }

    /// 从已经存下来的原图数据补生成缩略图（用于旧数据/导入数据）
    static func makeThumbnail(fromOriginal data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return thumbnailData(from: image)
    }

    /// 等比缩放，长边不超过 maxDimension；已经够小的图原样返回，避免无谓重绘
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
