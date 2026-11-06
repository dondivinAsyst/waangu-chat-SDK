import UIKit

/// In-memory chat image cache shared by the bubbles, the shared-media grid and
/// the media viewer.
///
/// `NSCache` rather than a dictionary so entries are evicted under memory
/// pressure instead of growing without bound in long conversations.
///
/// Previously lived as a `static` on `BubbleImageView`, which meant every other
/// consumer had to import a bubble view to reach the cache.
final class ChatImageMemoryCache {

    static let shared = ChatImageMemoryCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // ~50 MB
        return cache
    }()

    init() {}

    func store(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.cacheCost)
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// For a view-once photo once it has been seen: nothing of it stays in memory.
    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

// MARK: - UIImage Cache Cost

extension UIImage {
    /// Approximate uncompressed memory footprint in bytes.
    var cacheCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
