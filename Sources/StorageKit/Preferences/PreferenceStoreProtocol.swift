//
//  PreferenceStoreProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Contrat de stockage clé-valeur non sensible (UserDefaults, etc.).
///
/// Toutes les méthodes sont synchrones : UserDefaults est thread-safe
/// en lecture/écriture (backed by plist + atomic writes).
///
/// Les clés sont des `String` génériques — chaque module définit
/// ses propres namespaces (ex: `UserDefaultsKeys` dans l'app).
 public protocol PreferenceStoreProtocol: Sendable {

    // MARK: - Write

    func set(_ value: Any?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func set(_ value: String, forKey key: String)

    /// Encode un objet `Codable` en JSON avant stockage.
    func setCodable<T: Codable & Sendable>(_ value: T, forKey key: String) throws

    // MARK: - Read

    func bool(forKey key: String, default defaultValue: Bool) -> Bool
    func int(forKey key: String, default defaultValue: Int) -> Int
    func double(forKey key: String, default defaultValue: Double) -> Double
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func object(forKey key: String) -> Any?

    /// Décode un objet `Codable` depuis le JSON stocké.
    func getCodable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) throws -> T?

    // MARK: - Delete

    func remove(forKey key: String)
    func removeAll(forKeys keys: [String])
    func removeAll()

    // MARK: - Query

    func contains(key: String) -> Bool
}
