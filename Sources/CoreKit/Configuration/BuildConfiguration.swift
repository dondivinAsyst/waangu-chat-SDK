//
//  BuildConfiguration.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// MARK: - CoreKit/Configuration/BuildConfiguration.swift
//
// Configuration de build — détection de l'environnement de compilation.
//
// Améliorations vs version originale :
// 1. sentryDSN supprimé — les DSN ne doivent jamais être dans le code versionné.
//    La clé de production était exposée dans le code source.
//    Solution : lire depuis Info.plist (injecté via xcconfig) ou EnvironmentManager.
// 2. Les configs Sentry (DSN, tracesSampleRate) vivent dans ObservabilityKit
//    qui les lit via EnvironmentManager.getString(for: "SENTRY_DSN")
// 3. `Sendable` — utilisé dans des contextes concurrents

import Foundation

public enum BuildConfiguration: Sendable {
    case debug
    case staging
    case production

    // MARK: - Current

    public static var current: BuildConfiguration {
        #if DEBUG
        return .debug
        #elseif STAGING
        return .staging
        #else
        return .production
        #endif
    }

    // MARK: - Helpers

    public var isDebug: Bool      { self == .debug }
    public var isStaging: Bool    { self == .staging }
    public var isProduction: Bool { self == .production }

    /// `true` si les logs verbeux sont activés.
    public var isVerboseLoggingEnabled: Bool {
        switch self {
        case .debug:      return true
        case .staging:    return true
        case .production: return false
        }
    }

    /// Taux d'échantillonnage des traces de performance.
    /// Utilisé par ObservabilityKit — pas de référence Sentry ici.
    public var tracesSampleRate: Double {
        switch self {
        case .debug:      return 1.0
        case .staging:    return 0.5
        case .production: return 0.1
        }
    }
}

// MARK: - Comment sur sentryDSN
//
// Le DSN Sentry NE DOIT PAS être dans le code source.
// Il doit être injecté via xcconfig → Info.plist → EnvironmentManager :
//
// 1. Créer Config/Debug.xcconfig :
//    SENTRY_DSN = https://your-debug-dsn@sentry.io/1
//
// 2. Dans Info.plist :
//    <key>SENTRY_DSN</key>
//    <string>$(SENTRY_DSN)</string>
//
// 3. Dans ObservabilityKit/SentryProvider.swift :
//    let dsn = EnvironmentManager.shared.getString(for: "SENTRY_DSN")
//
// Les xcconfig ne sont pas versionnés (.gitignore) — la clé reste privée.
