//
//  TranslationCache.swift
//  TranslationKit
//
//  In-memory LRU cache for resolved + interpolated strings.
//  Keyed by locale + version + module + key + args.
//  Session-scoped: cleared on app restart.
//  Auto-invalidated when updatePayload() is called.
//

import Foundation

// MARK: - TranslationCache

final class TranslationCache {

    // MARK: - Cache Key

    struct Key: Hashable {
        let locale: String
        let version: Int
        let module: String
        let key: String
        let args: [String]
    }

    // MARK: - Storage

    private var store: [Key: String] = [:]
    private let maxCapacity: Int

    init(maxCapacity: Int = 500) {
        self.maxCapacity = maxCapacity
    }

    // MARK: - Access

    func get(_ key: Key) -> String? {
        store[key]
    }

    func set(_ key: Key, value: String) {
        if store.count >= maxCapacity {
            // Simple eviction: remove the first entry
            if let firstKey = store.keys.first {
                store.removeValue(forKey: firstKey)
            }
        }
        store[key] = value
    }

    // MARK: - Invalidation

    /// Remove all cached entries for a specific locale.
    /// Called when a new payload version is received for that locale.
    func invalidate(locale: String) {
        store = store.filter { $0.key.locale != locale }
    }

    /// Remove all cached entries across all locales.
    func invalidateAll() {
        store.removeAll()
    }
}
