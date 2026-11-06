//
//  PreferenceStore.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Implémentation de `PreferenceStoreProtocol` basée sur UserDefaults.
///
/// UserDefaults est thread-safe en lecture/écriture, donc pas besoin
/// d'actor. La classe est marquée `Sendable` car `UserDefaults` est
/// thread-safe et les propriétés stockées sont immuables.
///
/// Usage :
/// ```swift
/// let prefs = PreferenceStore()  // .standard
/// prefs.set("dark", forKey: "preferences.colorScheme")
/// let scheme = prefs.string(forKey: "preferences.colorScheme")
///
/// // Codable support
/// try prefs.setCodable(myConfig, forKey: "app.config")
/// let config: MyConfig? = try prefs.getCodable(MyConfig.self, forKey: "app.config")
/// ```
public final class PreferenceStore: PreferenceStoreProtocol, @unchecked Sendable {

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - suiteName: Suite UserDefaults. `nil` = `.standard`.
    ///                Passer un nom custom en test pour isoler le storage.
    public init(suiteName: String? = nil) {
        if let suiteName {
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            self.defaults = .standard
        }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Write (primitifs)

    public func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - Write (Codable)

    public func setCodable<T: Codable & Sendable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }

    // MARK: - Read (primitifs)

    public func bool(forKey key: String, default defaultValue: Bool = false) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    public func int(forKey key: String, default defaultValue: Int = 0) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.integer(forKey: key)
    }

    public func double(forKey key: String, default defaultValue: Double = 0) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.double(forKey: key)
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    // MARK: - Read (Codable)

    public func getCodable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try decoder.decode(type, from: data)
    }

    // MARK: - Delete

    public func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    public func removeAll(forKeys keys: [String]) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    public func removeAll() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: bundleId)
    }

    // MARK: - Query

    public func contains(key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }
}
