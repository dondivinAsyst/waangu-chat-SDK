// MARK: - CoreKit/Realtime/OfflineQueueProtocol.swift
//
// Module  : CoreKit
// Rôle    : Contrat pour la file d'attente de messages hors ligne.
//           DIFFÉRENT du retry HTTP : en HTTP une requête échoue et on retry.
//           En realtime, l'utilisateur tape 15 messages hors ligne →
//           ils doivent TOUS partir dans l'ordre à la reconnexion.
//
// Design  : FIFO strict par topic.
//           Persistée via StorageKit (survive app kill).
//           TTL par message (ne pas envoyer un typing indicator vieux de 10 min).
//           Taille max configurable (ne pas accumuler 10000 positions GPS).
//
// Implémentation : Dans RealtimeKit (OfflineMessageQueue), pas dans CoreKit.

import Foundation

// MARK: - OfflineQueueProtocol

/// File d'attente pour les messages envoyés pendant une déconnexion.
///
/// Les messages sont persistés (survive à un app kill) et envoyés
/// dans l'ordre (FIFO) à la reconnexion.
///
/// ```swift
/// // Le RealtimeClient enqueue automatiquement quand il est déconnecté :
/// // → l'appelant reçoit .reconnecting, le message part à la reconnexion.
///
/// // Consultation de l'état de la file :
/// let pending = await realtime.offlineQueue.pendingCount
/// let items = await realtime.offlineQueue.pendingItems()
/// ```
public protocol OfflineQueueProtocol: Sendable {

    /// Ajoute un message à la file d'attente.
    ///
    /// Le message est sérialisé et persisté immédiatement.
    /// Le TTL est lu depuis l'item pour purger les messages expirés au flush.
    ///
    /// - Parameter item: Le message à mettre en file.
    /// - Throws: `RealtimeError.offlineQueueFull` si la taille max est atteinte.
    func enqueue(_ item: OfflineQueueItem) async throws

    /// Envoie tous les messages pendants (FIFO) via le handler fourni.
    ///
    /// Les messages dont le TTL est expiré sont purgés avant l'envoi.
    /// Les messages envoyés avec succès sont retirés de la file.
    /// Les messages qui échouent restent en file pour le prochain flush.
    ///
    /// - Parameter handler: Closure appelée pour chaque message.
    ///                      Retourne `true` si l'envoi a réussi.
    /// - Returns: Le résultat du flush (envoyés, expirés, échoués).
    @discardableResult
    func flush(
        handler: @Sendable (OfflineQueueItem) async throws -> Bool
    ) async -> OfflineFlushResult

    /// Nombre de messages en attente.
    var pendingCount: Int { get async }

    /// Liste les messages en attente (pour affichage UI ou debugging).
    func pendingItems() async -> [OfflineQueueItem]

    /// Supprime tous les messages en attente.
    func clear() async

    /// Supprime les messages expirés (TTL dépassé) sans les envoyer.
    ///
    /// - Returns: Nombre de messages purgés.
    @discardableResult
    func purgeExpired() async -> Int

    /// Supprime tous les messages d'un topic donné.
    ///
    /// Utile quand une feature se désabonne et ne veut plus envoyer ses messages pendants.
    func clear(for topic: RealtimeTopic) async
}

// MARK: - OfflineQueueItem

/// Un message dans la file d'attente hors ligne.
///
/// Porte le payload sérialisé (Data) car le type générique du message
/// n'est plus disponible après la sérialisation.
public struct OfflineQueueItem: Sendable, Identifiable, Codable {

    /// Identifiant unique (même MessageID que le message original).
    public let id: MessageID

    /// Topic de destination.
    public let topic: RealtimeTopic

    /// Payload sérialisé en JSON Data.
    public let payloadData: Data

    /// QoS demandé.
    public let qos: RealtimeQoS

    /// Priorité du message.
    public let priority: MessagePriority

    /// Timestamp de création du message.
    public let timestamp: Date

    /// TTL du message. `nil` = pas d'expiration.
    public let ttl: TimeInterval?

    /// Metadata du message (traceId, deviceId, etc.).
    public let metadata: [String: String]

    // MARK: - Init

    public init(
        id: MessageID,
        topic: RealtimeTopic,
        payloadData: Data,
        qos: RealtimeQoS,
        priority: MessagePriority,
        timestamp: Date = Date(),
        ttl: TimeInterval? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.topic = topic
        self.payloadData = payloadData
        self.qos = qos
        self.priority = priority
        self.timestamp = timestamp
        self.ttl = ttl
        self.metadata = metadata
    }

    /// `true` si le message a dépassé son TTL.
    public func isExpired(at now: Date = Date()) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(timestamp) > ttl
    }

    /// Âge du message en secondes.
    public func age(at now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(timestamp)
    }
}

// MARK: - OfflineFlushResult

/// Résultat d'un flush de la file hors ligne.
public struct OfflineFlushResult: Sendable {

    /// Nombre de messages envoyés avec succès.
    public let sentCount: Int

    /// Nombre de messages purgés (TTL expiré).
    public let expiredCount: Int

    /// Nombre de messages qui ont échoué et restent en file.
    public let failedCount: Int

    /// Durée totale du flush.
    public let duration: TimeInterval

    public init(
        sentCount: Int,
        expiredCount: Int,
        failedCount: Int,
        duration: TimeInterval
    ) {
        self.sentCount = sentCount
        self.expiredCount = expiredCount
        self.failedCount = failedCount
        self.duration = duration
    }

    /// Nombre total de messages traités.
    public var totalProcessed: Int {
        sentCount + expiredCount + failedCount
    }
}

// MARK: - OfflineQueueConfiguration

/// Configuration de la file d'attente hors ligne.
///
/// Passée au bootstrap via RealtimeAssembly.
public struct OfflineQueueConfiguration: Sendable {

    /// Nombre maximum de messages dans la file.
    /// Au-delà, les nouveaux messages les moins prioritaires sont droppés.
    public let maxSize: Int

    /// Durée maximale de rétention (en secondes).
    /// Les messages plus vieux sont purgés au prochain flush.
    public let maxRetention: TimeInterval

    /// Si `true`, la file est persistée sur disque (survive app kill).
    /// Si `false`, la file est en mémoire uniquement.
    public let persistent: Bool

    // MARK: - Init

    public init(
        maxSize: Int = 500,
        maxRetention: TimeInterval = 3600,  // 1 heure
        persistent: Bool = true
    ) {
        self.maxSize = maxSize
        self.maxRetention = maxRetention
        self.persistent = persistent
    }

    // MARK: - Presets

    /// Config pour le chat : file large, rétention longue, persistée.
    public static let chat = OfflineQueueConfiguration(
        maxSize: 1000,
        maxRetention: 86400,   // 24h
        persistent: true
    )

    /// Config pour le tracking : file petite, rétention courte, mémoire.
    public static let tracking = OfflineQueueConfiguration(
        maxSize: 100,
        maxRetention: 300,     // 5 min
        persistent: false
    )

    /// Config par défaut.
    public static let `default` = OfflineQueueConfiguration()
}
