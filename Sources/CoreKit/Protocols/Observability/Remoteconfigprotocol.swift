//
//  Remoteconfigprotocol.swift
//  AppModules
//
//  Created by Asyst on 6/5/26.
//

// MARK: - CoreKit/Observability/RemoteConfigProtocol.swift
//
// Module  : CoreKit
// Rôle    : Contrat pour la configuration à distance (feature flags, kill switches).
//           Les features ne savent pas si c'est Firebase Remote Config,
//           LaunchDarkly, ou un fichier JSON local.
//
// Usage typique :
//   - Kill switch du certificate pinning
//   - Activer/désactiver une feature progressivement (rollout)
//   - A/B testing
//   - Forcer une version minimum de l'app

import Foundation

// MARK: - RemoteConfigProtocol

/// Contrat pour la configuration à distance.
///
/// ```swift
/// // FeatureMarketplace — import CoreKit
/// class MarketplaceViewModel {
///     private let remoteConfig: any RemoteConfigProtocol
///
///     var isDeliveryTrackingEnabled: Bool {
///         remoteConfig.bool(forKey: "marketplace_delivery_tracking")
///     }
/// }
/// ```
public protocol RemoteConfigProtocol: Sendable {

    /// Récupère une valeur string. Retourne le `defaultValue` si absent.
    func string(forKey key: String, defaultValue: String) -> String

    /// Récupère une valeur booléenne. Retourne `false` si absent.
    func bool(forKey key: String) -> Bool

    /// Récupère une valeur numérique. Retourne `0` si absent.
    func number(forKey key: String) -> Double

    /// Récupère du JSON décodé en type Swift.
    func decoded<T: Decodable>(forKey key: String, as type: T.Type) -> T?

    /// Force un refresh des valeurs depuis le serveur.
    func refresh() async throws

    /// Timestamp du dernier fetch réussi.
    var lastFetchTime: Date? { get }
}

// MARK: - Convenience

extension RemoteConfigProtocol {

    /// String avec default vide.
    public func string(forKey key: String) -> String {
        string(forKey: key, defaultValue: "")
    }

    /// Vérifie si une feature est activée (par string key).
    public func isFeatureEnabled(_ key: String) -> Bool {
        bool(forKey: key)
    }

    /// Vérifie si une feature est activée (type-safe).
    ///
    /// ```swift
    /// if remoteConfig.isEnabled(.wallet) { ... }
    /// if remoteConfig.isEnabled(.ride) { ... }
    /// ```
    public func isEnabled(_ feature: Feature) -> Bool {
        bool(forKey: feature.configKey)
    }
}

// MARK: - Feature (Kill Switch type-safe)

/// Enum de toutes les features de Waangu.
///
/// Chaque feature a un kill switch configurable à distance
/// via Firebase Remote Config ou le backend.
///
/// Convention de clé : `feature_{rawValue}_enabled`
///
/// ```swift
/// // TabBar
/// if remoteConfig.isEnabled(.ride)        { RideTab() }
/// if remoteConfig.isEnabled(.wallet)      { WalletTab() }
/// if remoteConfig.isEnabled(.chat)        { ChatTab() }
///
/// // Navigation guard
/// guard remoteConfig.isEnabled(.marketplace) else {
///     showFeatureDisabledScreen()
///     return
/// }
/// ```
public enum Feature: String, CaseIterable, Sendable {
    case ride
    case chat
    case wallet
    case marketplace
    case doctorConsult
    case insurance
    case electricityWater
    case bookingTickets
    case homeRental

    /// Clé Remote Config générée automatiquement.
    /// `.wallet` → `"feature_wallet_enabled"`
    /// `.doctorConsult` → `"feature_doctorConsult_enabled"`
    public var configKey: String { "feature_\(rawValue)_enabled" }
}

// MARK: - Remote Config Keys

/// Clés de configuration centralisées (hors kill switches features).
///
/// Les kill switches features passent par `Feature.configKey`.
/// Ces clés sont pour les configs techniques transversales.
public enum RemoteConfigKey {
    // ── Sécurité ─────────────────────────────────
    public static let tlsPinningEnabled = "tls_pinning_enabled"

    // ── App lifecycle ────────────────────────────
    public static let forceUpdateMinVersion = "force_update_min_version"
    public static let maintenanceMode = "maintenance_mode"

    // ── Realtime ─────────────────────────────────
    public static let realtimeCompressionEnabled = "realtime_compression_enabled"

    // ── Observabilité ────────────────────────────
    public static let sentrySampleRate = "sentry_sample_rate"
}
