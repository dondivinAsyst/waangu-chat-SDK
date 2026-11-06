//
//  EnvironmentManager.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation

/// Lecture des variables d'environnement et Info.plist.
/// Point d'entrée unique pour toute valeur de configuration externe.
///
/// ProcessInfo a la priorité — permet l'override en CI/CD et en tests.
/// Les clés app-spécifiques (SENTRY_DSN, FIREBASE_TOKEN…) sont lues
/// depuis le target App via `getString(for:)`, pas exposées ici.
public final class EnvironmentManager: Sendable {

    public static let shared = EnvironmentManager()
    private init() {}

    // MARK: - Lecture générique

    public func getString(for key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
            ?? Bundle.main.infoDictionary?[key] as? String
    }

    public func getBool(for key: String, default defaultValue: Bool = false) -> Bool {
        guard let value = getString(for: key) else { return defaultValue }
        return Bool(value) ?? defaultValue
    }

    public func getInt(for key: String) -> Int? {
        guard let value = getString(for: key) else { return nil }
        return Int(value)
    }

    public func getDouble(for key: String) -> Double? {
        guard let value = getString(for: key) else { return nil }
        return Double(value)
    }
}
