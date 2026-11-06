//
//  ChatMediaPreviewCache.swift
//  FeatureChat
//

import UIKit

/// Decoded inline previews, keyed by `codeMessage`.
///
/// Every media message carries a tiny JPEG preview inline — `imageToDataURL`
/// produces it at send time, 150px and quality 0.005, so a couple of kilobytes —
/// and it travels with the message row. It needs no disk read and no network
/// call: by the time a bubble exists, its preview is already in memory as a
/// base64 string.
///
/// That string still has to be base64-decoded and turned into a `UIImage`, which
/// is too slow to redo on every appearance while scrolling. This holds the
/// decoded result so the second and every later appearance is a dictionary
/// lookup, which is what lets the bubble paint content on its very first frame
/// instead of showing an empty placeholder and popping in later.
///
/// Separate from `ChatImageMemoryCache`, which holds full-resolution images: a
/// preview must never be mistaken for the real thing and stop the upgrade.
final class ChatMediaPreviewCache {

    static let shared = ChatMediaPreviewCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Previews are ~150px, so a generous count still costs little.
        cache.countLimit = 600
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    /// Keys we have already tried and failed to decode, so a malformed preview is
    /// not re-decoded on every single appearance of its row.
    private let failures = NSCache<NSString, NSNull>()

    init() {
        failures.countLimit = 600
    }

    /// The decoded preview for a message, decoding it now if this is the first ask.
    ///
    /// Safe to call from a view's initializer: the work is a base64 decode of a
    /// couple of kilobytes, and it only ever happens once per message.
    func preview(forKey key: String, encoded: String?) -> UIImage? {
        let nsKey = key as NSString

        if let cached = cache.object(forKey: nsKey) { return cached }
        if failures.object(forKey: nsKey) != nil { return nil }

        guard let encoded, !encoded.isEmpty else { return nil }

        guard let decoded = decodeBase64ToUIImage(encoded) else {
            // Not base64 — a remote URL or a file path, which some senders store
            // here instead. Those resolve on the background path like any other
            // image; remember the miss so we stop retrying it.
            failures.setObject(NSNull(), forKey: nsKey)
            return nil
        }

        cache.setObject(decoded, forKey: nsKey, cost: decoded.cacheCost)
        return decoded
    }

    /// Whether a decoded preview is already in hand — no decoding triggered.
    /// For a view-once photo once it has been seen: nothing of it stays in memory.
    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
        failures.removeObject(forKey: key as NSString)
    }

    func cachedPreview(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
}
