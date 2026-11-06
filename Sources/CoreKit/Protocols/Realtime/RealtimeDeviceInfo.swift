// MARK: - CoreKit/Realtime/RealtimeDeviceInfo.swift
//
// Module  : CoreKit
// Rôle    : Identité du device pour le multi-device awareness.
//           Porté dans chaque connexion et chaque message de presence.
//           Permet de distinguer iPhone vs iPad connectés simultanément.
//
// Design  : Value type immuable fourni au bootstrap via DependencyContainer.
//           Le deviceId est unique par installation (pas par device physique)
//           pour gérer les réinstallations.

import Foundation

// MARK: - RealtimeDeviceInfo

/// Informations sur le device courant, portées par chaque connexion temps réel.
///
/// Utilisé pour :
/// - Distinguer les connexions multi-device (iPhone + iPad)
/// - Filtrer les messages de presence (ne pas se notifier soi-même)
/// - Router les read receipts vers les bonnes instances
///
/// ```swift
/// // Fourni au bootstrap dans DependencyContainer :
/// let deviceInfo = RealtimeDeviceInfo(
///     deviceId: keychain.getOrCreateDeviceId(),
///     platform: "iOS",
///     appVersion: Bundle.main.appVersion
/// )
/// ```
public struct RealtimeDeviceInfo: Sendable, Equatable, Codable {

    /// Identifiant unique de cette installation.
    ///
    /// Généré une fois au premier lancement, persisté dans le Keychain.
    /// Survit aux mises à jour de l'app mais pas aux réinstallations.
    public let deviceId: String

    /// Plateforme du device (ex: "iOS", "iPadOS", "macOS").
    public let platform: String

    /// Version de l'app (ex: "2.4.1").
    public let appVersion: String

    /// Modèle du device (ex: "iPhone15,2").
    /// Optionnel — utile pour le debugging et les métriques.
    public let deviceModel: String?

    // MARK: - Init

    public init(
        deviceId: String,
        platform: String,
        appVersion: String,
        deviceModel: String? = nil
    ) {
        self.deviceId = deviceId
        self.platform = platform
        self.appVersion = appVersion
        self.deviceModel = deviceModel
    }
}

// MARK: - CustomStringConvertible

extension RealtimeDeviceInfo: CustomStringConvertible {
    public var description: String {
        "\(platform)/\(appVersion) (\(deviceId.prefix(8))…)"
    }
}
