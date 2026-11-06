// MARK: - CoreKit/Realtime/RealtimeMessage.swift
//
// Module  : CoreKit
// Rôle    : Modèle de message temps réel complet.
//           Porte l'identité (dédup), la corrélation (request-reply),
//           le TTL (offline queue cleanup), la priorité, et les métadonnées (tracing).
//
// Design  : Generic sur le Payload pour le type-safety.
//           Le MessageID est un UUID client-side pour la déduplication.
//           Le correlationId lie une requête à sa réponse (request-reply pattern).
//           Le metadata porte le traceId (OpenTelemetry) et des headers custom.

import Foundation

// MARK: - MessageID

/// Identifiant unique d'un message temps réel.
///
/// Généré côté client (UUID) pour la déduplication.
/// Le broker peut attribuer un server-side ID séparé dans `serverMessageId`.
public typealias MessageID = UUID

// MARK: - MessagePriority

/// Priorité d'un message pour l'ordering et le traitement.
///
/// Les transports qui supportent la priorisation (ex: MQTT 5 user properties)
/// propagent cette info. Les autres l'ignorent gracieusement.
public enum MessagePriority: Int, Sendable, Comparable, Codable, CaseIterable {

    /// Informations non urgentes (analytics, sync passive).
    case low = 0

    /// Messages standard (chat, updates).
    case normal = 1

    /// Messages importants (statut de commande, trip updates).
    case high = 2

    /// Messages critiques (notifications financières, alertes sécurité).
    /// Jamais droppés par la backpressure, jamais mis en offline queue avec TTL.
    case critical = 3

    public static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - RealtimeQoS

/// Niveau de qualité de service pour la délivrance des messages.
///
/// Abstraction technologie-agnostique. Chaque transport mappe ces niveaux
/// vers son implémentation native :
/// - MQTT : QoS 0, 1, 2
/// - WebSocket : implémenté via ack applicatif côté RealtimeKit
/// - InMemory : tous les niveaux sont équivalents (délivrance immédiate)
public enum RealtimeQoS: Int, Sendable, Comparable, Codable, CaseIterable {

    /// Fire-and-forget. Aucune garantie de délivrance.
    /// Usage : GPS haute fréquence, typing indicators.
    case fireAndForget = 0

    /// At-least-once. Le message est délivré au moins une fois (possibles doublons).
    /// Usage : messages chat, notifications de transaction.
    /// ⚠️ Nécessite la déduplication côté récepteur (MessageDeduplicator dans RealtimeKit).
    case atLeastOnce = 1

    /// Exactly-once. Le message est délivré exactement une fois.
    /// Usage : opérations financières critiques.
    /// ⚠️ Plus coûteux en latence (handshake supplémentaire).
    case exactlyOnce = 2

    public static func < (lhs: RealtimeQoS, rhs: RealtimeQoS) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - RealtimeMessage

/// Message temps réel typé.
///
/// Porte toutes les métadonnées nécessaires pour la déduplication,
/// le request-reply, le TTL, la priorisation, et le distributed tracing.
///
/// ```swift
/// // Envoi typé — le RealtimeClient encode automatiquement :
/// try await realtime.publish(chatMessage, to: topic, qos: .atLeastOnce, priority: .normal)
///
/// // Réception typée — le RealtimeClient décode automatiquement :
/// let (stream, token) = try await realtime.subscribe(to: topic, as: ChatMessage.self, ...)
/// ```
public struct RealtimeMessage<Payload: Codable & Sendable>: Sendable, Identifiable {

    // MARK: - Identity

    /// Identifiant unique client-side. Utilisé pour la déduplication.
    public let id: MessageID

    /// Identifiant attribué par le serveur/broker (si disponible).
    public let serverMessageId: String?

    // MARK: - Routing

    /// Topic sur lequel le message est publié/reçu.
    public let topic: RealtimeTopic

    /// Payload typé du message.
    public let payload: Payload

    /// Niveau de qualité de service.
    public let qos: RealtimeQoS

    // MARK: - Correlation (Request-Reply)

    /// Identifiant de corrélation pour le pattern request-reply.
    ///
    /// Quand un message est une requête, le `correlationId` est copié
    /// dans la réponse pour les associer.
    /// `nil` pour les messages pub/sub classiques.
    public let correlationId: MessageID?

    /// Topic sur lequel la réponse est attendue (request-reply).
    /// `nil` pour les messages pub/sub classiques.
    public let replyTopic: RealtimeTopic?

    // MARK: - Timestamps

    /// Timestamp de création côté client.
    public let timestamp: Date

    /// Timestamp attribué par le serveur/broker (si disponible).
    /// Utilisé pour l'ordering côté serveur.
    public let serverTimestamp: Date?

    // MARK: - Lifecycle

    /// Time-to-live du message.
    ///
    /// Les messages dans l'offline queue dont le TTL est expiré
    /// sont purgés avant le flush à la reconnexion.
    /// `nil` = durée de vie infinie.
    public let ttl: TimeInterval?

    /// Priorité du message.
    public let priority: MessagePriority

    // MARK: - Metadata

    /// Métadonnées key-value pour le distributed tracing et les headers custom.
    ///
    /// Clés réservées :
    /// - `"traceId"` : identifiant OpenTelemetry pour le tracing end-to-end
    /// - `"deviceId"` : identifiant du device émetteur
    /// - `"userId"` : identifiant de l'utilisateur émetteur
    public let metadata: [String: String]

    // MARK: - Init

    public init(
        id: MessageID = MessageID(),
        serverMessageId: String? = nil,
        topic: RealtimeTopic,
        payload: Payload,
        qos: RealtimeQoS = .atLeastOnce,
        correlationId: MessageID? = nil,
        replyTopic: RealtimeTopic? = nil,
        timestamp: Date = Date(),
        serverTimestamp: Date? = nil,
        ttl: TimeInterval? = nil,
        priority: MessagePriority = .normal,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.serverMessageId = serverMessageId
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.correlationId = correlationId
        self.replyTopic = replyTopic
        self.timestamp = timestamp
        self.serverTimestamp = serverTimestamp
        self.ttl = ttl
        self.priority = priority
        self.metadata = metadata
    }
}

// MARK: - TTL Helpers

extension RealtimeMessage {

    /// `true` si le message a dépassé son TTL.
    ///
    /// Utilisé par l'offline queue pour purger les messages expirés avant le flush.
    public func isExpired(at now: Date = Date()) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(timestamp) > ttl
    }

    /// Temps restant avant expiration. `nil` si pas de TTL.
    public func remainingTTL(at now: Date = Date()) -> TimeInterval? {
        guard let ttl else { return nil }
        let remaining = ttl - now.timeIntervalSince(timestamp)
        return max(0, remaining)
    }
}

// MARK: - Metadata Helpers

extension RealtimeMessage {

    /// Le traceId OpenTelemetry, s'il est présent dans les metadata.
    public var traceId: String? {
        metadata["traceId"]
    }

    /// Le deviceId de l'émetteur, s'il est présent dans les metadata.
    public var senderDeviceId: String? {
        metadata["deviceId"]
    }

    /// L'userId de l'émetteur, s'il est présent dans les metadata.
    public var senderUserId: String? {
        metadata["userId"]
    }
}

// MARK: - Equatable (by ID)

extension RealtimeMessage: Equatable where Payload: Equatable {
    public static func == (lhs: RealtimeMessage, rhs: RealtimeMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable (by ID)

extension RealtimeMessage: Hashable where Payload: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
