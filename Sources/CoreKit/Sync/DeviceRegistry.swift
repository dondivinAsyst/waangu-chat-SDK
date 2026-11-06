//
//  DeviceRegistry.swift
//  CoreKit
//
//  Multi-device, sessions et liaison du step-up — Bloc 8, §18 et §19.
//
//  **BACKEND CONTRACT REQUIRED** — `GET /v1/sessions`, `DELETE /v1/sessions/{id}`.
//
//  Ferme la moitié contractuelle de P0-3. Le câblage de `DeviceRevocationGuard`
//  et de `ResumeToken` reste à faire et exige un compilateur.
//

import Foundation

// MARK: - Plateforme

public enum DevicePlatform: String, Codable, Sendable, Hashable, CaseIterable {
    case iOS     = "IOS"
    case android = "ANDROID"
    case web     = "WEB"
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DevicePlatform(rawValue: raw) ?? .unknown
    }
}

/// Ce que vaut un appareil.
public enum DeviceTrustLevel: String, Codable, Sendable, Hashable, CaseIterable {

    /// Enrôlé et vérifié.
    case trusted    = "TRUSTED"

    /// Connu, pas encore vérifié.
    case known      = "KNOWN"

    /// Vu pour la première fois.
    case new        = "NEW"

    /// Signalé — jailbreak, incohérence d'attestation.
    case suspicious = "SUSPICIOUS"

    /// Révoqué. Ne doit plus rien recevoir de sensible.
    case revoked    = "REVOKED"

    case unknown    = "UNKNOWN"

    /// Un niveau inconnu ne vaut pas `trusted`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeviceTrustLevel(rawValue: raw) ?? .unknown
    }

    /// Peut recevoir des données financières ou personnelles.
    ///
    /// L'invariant `REVOKED_DEVICE_CANNOT_SYNC_SENSITIVE_DATA` du §33 se réduit
    /// à cette propriété — encore faut-il que quelqu'un l'interroge.
    public var permitsSensitiveSync: Bool {
        self == .trusted || self == .known
    }

    /// Peut déclencher une mutation financière.
    public var permitsMutation: Bool { self == .trusted }
}

// MARK: - Session d'appareil (§18)

public struct DeviceSession: Codable, Sendable, Hashable, Identifiable {

    public let deviceID: String
    public var id: String { deviceID }

    public let platform: DevicePlatform
    public let appVersion: String
    public let sessionID: String

    /// Nom donné par l'utilisateur. `nil` ⇒ afficher le modèle, jamais un
    /// identifiant technique.
    public let displayName: String?

    public let createdAt: Date
    public let lastSeenAt: Date
    public let trustLevel: DeviceTrustLevel

    /// C'est l'appareil courant.
    public let isCurrent: Bool

    public init(deviceID: String, platform: DevicePlatform, appVersion: String,
                sessionID: String, displayName: String? = nil,
                createdAt: Date, lastSeenAt: Date,
                trustLevel: DeviceTrustLevel, isCurrent: Bool = false) {
        self.deviceID = deviceID
        self.platform = platform
        self.appVersion = appVersion
        self.sessionID = sessionID
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.trustLevel = trustLevel
        self.isCurrent = isCurrent
    }
}

// MARK: - Révocation

/// Ce qui doit se produire localement quand un appareil est révoqué.
///
/// Énuméré parce qu'une révocation qui coupe seulement le réseau laisse la
/// base locale en place : quiconque tient l'appareil garde l'historique, les
/// résumés financiers et les pièces jointes. Le §43 (backup/restore) ajoute que
/// ces données ne doivent pas non plus revenir par une restauration.
public struct DeviceRevocationEffect: Sendable, Hashable {

    /// Purger la base de conversation locale.
    public let purgesConversationCache: Bool

    /// Purger les résumés financiers en cache.
    public let purgesFinancialCache: Bool

    /// Effacer les identifiants du trousseau.
    public let clearsCredentials: Bool

    /// Annuler les souscriptions temps réel en cours.
    public let cancelsRealtimeSubscriptions: Bool

    /// Vider l'outbox sans la republier.
    ///
    /// **Sans republication.** Republier depuis un appareil révoqué est
    /// exactement ce que la révocation cherche à empêcher.
    public let discardsOutboxWithoutFlush: Bool

    public init(purgesConversationCache: Bool = true,
                purgesFinancialCache: Bool = true,
                clearsCredentials: Bool = true,
                cancelsRealtimeSubscriptions: Bool = true,
                discardsOutboxWithoutFlush: Bool = true) {
        self.purgesConversationCache = purgesConversationCache
        self.purgesFinancialCache = purgesFinancialCache
        self.clearsCredentials = clearsCredentials
        self.cancelsRealtimeSubscriptions = cancelsRealtimeSubscriptions
        self.discardsOutboxWithoutFlush = discardsOutboxWithoutFlush
    }

    /// Le défaut : tout purger.
    public static let complete = DeviceRevocationEffect()
}

// MARK: - Liaison du step-up (§19)

/// Ce à quoi une attestation doit correspondre pour valoir ici et maintenant.
///
/// Le §19 pose quatre liens. Une attestation biométrique obtenue sur iOS ne
/// doit jamais devenir une autorisation transférable vers Android, vers le Web,
/// vers une autre session ou vers un autre objet.
public struct StepUpBindingRequirement: Sendable, Hashable {

    public let expectedDeviceID: String
    public let expectedSessionID: String
    public let expectedCorrelationID: CorrelationId

    /// Âge maximal accepté. Le backend reste l'autorité sur la péremption ; ce
    /// plafond local est une seconde barrière, jamais la seule.
    public let maximumAge: TimeInterval

    public init(expectedDeviceID: String, expectedSessionID: String,
                expectedCorrelationID: CorrelationId,
                maximumAge: TimeInterval = 300) {
        self.expectedDeviceID = expectedDeviceID
        self.expectedSessionID = expectedSessionID
        self.expectedCorrelationID = expectedCorrelationID
        self.maximumAge = maximumAge
    }
}

/// Pourquoi une attestation ne vaut pas ici.
public enum StepUpBindingRejection: String, Error, Sendable, Hashable, CaseIterable {

    case wrongDevice   = "WRONG_DEVICE"
    case wrongSession  = "WRONG_SESSION"
    case wrongPurpose  = "WRONG_PURPOSE"
    case tooOld        = "TOO_OLD"

    /// L'attestation ne porte aucune session.
    ///
    /// Refusée plutôt qu'acceptée : une preuve qui ne dit pas à quelle session
    /// elle appartient vaut pour toutes, ce qui est précisément ce que le §19
    /// interdit.
    case unboundSession = "UNBOUND_SESSION"

    public var messageKey: String { "security.stepup.rejected.\(rawValue.lowercased())" }

    /// À remonter comme incident.
    public var isSecurityIncident: Bool {
        self == .wrongDevice || self == .wrongSession || self == .wrongPurpose
    }
}

public extension StepUpAttestation {

    /// Vérifie les quatre liens du §19.
    ///
    /// Rend `nil` quand l'attestation vaut pour cette opération.
    func bindingRejection(
        against requirement: StepUpBindingRequirement,
        now: Date = Date()
    ) -> StepUpBindingRejection? {

        guard deviceID == requirement.expectedDeviceID else { return .wrongDevice }

        guard let sessionID else { return .unboundSession }
        guard sessionID == requirement.expectedSessionID else { return .wrongSession }

        guard correlationID == requirement.expectedCorrelationID else { return .wrongPurpose }

        guard now.timeIntervalSince(satisfiedAt) <= requirement.maximumAge else { return .tooOld }

        return nil
    }
}

// MARK: - Contrat (§18, §24)

/// Le registre des appareils.
public protocol DeviceRegistryProviding: Sendable {

    /// Les sessions actives. `GET /v1/sessions`.
    func sessions() async -> Result<[DeviceSession], SyncError>

    /// Renomme un appareil.
    func rename(deviceID: String, to name: String) async -> Result<Void, SyncError>

    /// Révoque une session. `DELETE /v1/sessions/{id}`.
    func revoke(deviceID: String) async -> Result<DeviceRevocationEffect, SyncError>

    /// Déconnecte tout, y compris l'appareil courant.
    func revokeAll() async -> Result<DeviceRevocationEffect, SyncError>

    /// Notifie qu'une session inconnue est apparue sur le compte.
    ///
    /// Flux, et non requête : une nouvelle session est un événement de sécurité
    /// que l'utilisateur doit voir arriver, pas une information qu'il doit
    /// penser à aller chercher.
    func newSessionAlerts() -> AsyncStream<DeviceSession>
}

// MARK: - Défaut fermé

/// Ne connaît aucun appareil.
///
/// `revoke` rend `capabilityUnavailable` plutôt qu'un succès : afficher « cet
/// appareil a été déconnecté » sans que rien ne le soit est pire que d'afficher
/// une erreur.
public struct ClosedDeviceRegistry: DeviceRegistryProviding {

    public init() {}

    public func sessions() async -> Result<[DeviceSession], SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func rename(deviceID: String, to name: String) async -> Result<Void, SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func revoke(deviceID: String) async -> Result<DeviceRevocationEffect, SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func revokeAll() async -> Result<DeviceRevocationEffect, SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func newSessionAlerts() -> AsyncStream<DeviceSession> {
        AsyncStream { $0.finish() }
    }
}
