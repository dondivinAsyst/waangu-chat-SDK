// MARK: - NetworkKit/Services/CacheStore.swift
//
// Cache en mémoire avec TTL — utilisé pour les réponses qui ne passent pas
// par URLCache (endpoints non-HTTP, réponses custom...).
// Pour le cache HTTP standard, URLCache est utilisé via CacheMiddleware.

import Foundation

actor CacheStore {

    struct Entry {
        let data: Data
        let expiry: Date

        var isExpired: Bool { expiry < Date() }
    }

    private var store: [String: Entry] = [:]

    func set(_ data: Data, for key: String, ttl: TimeInterval) {
        store[key] = Entry(data: data, expiry: Date().addingTimeInterval(ttl))
    }

    func get(_ key: String) -> Data? {
        guard let entry = store[key] else { return nil }
        if entry.isExpired {
            store[key] = nil
            return nil
        }
        return entry.data
    }

    func invalidate(_ key: String) {
        store[key] = nil
    }

    func clear() {
        store.removeAll()
    }

    /// Nombre d'entrées actives (non expirées).
    func activeCount() -> Int {
        store.values.filter { !$0.isExpired }.count
    }
}
