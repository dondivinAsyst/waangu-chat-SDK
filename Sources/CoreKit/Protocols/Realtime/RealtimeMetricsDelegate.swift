// MARK: - CoreKit/Realtime/RealtimeMetricsDelegate.swift
//
// Module  : CoreKit
// Rôle    : Contrat d'observabilité pour l'infrastructure temps réel.
//           Le delegate est injecté dans RealtimeClient et appelé à chaque événement
//           significatif. L'implémentation (dans l'App Target ou un MetricsKit)
//           route vers Firebase Analytics, Datadog, OSSignpost, ou console.
//
// Design  : Même pattern que les métriques database (OSSignpost + callbacks).
//           Chaque message porte un traceId dans ses metadata pour le
//           distributed tracing (OpenTelemetry-compatible).

import Foundation

// MARK: - RealtimeMetricsDelegate

/// Delegate pour l'observabilité de l'infrastructure temps réel.
///
/// Toutes les méthodes ont des implémentations par défaut (no-op)
/// pour permettre une adoption progressive.
///
/// ```swift
/// // App Target — implémentation concrète
/// final class AppRealtimeMetrics: RealtimeMetricsDelegate {
///     func didReceiveMessage(topic:latency:size:) {
///         OSSignposter.default.emitEvent("realtime.receive", "\(topic)")
///         Datadog.log(metric: "realtime.message.latency", value: latency)
///     }
/// }
/// ```
public protocol RealtimeMetricsDelegate: Sendable {

    // MARK: - Messages

    /// Un message a été reçu sur un topic.
    ///
    /// - Parameters:
    ///   - topic: Le topic d'origine.
    ///   - latency: Temps entre le serverTimestamp et la réception locale (si disponible).
    ///   - size: Taille du payload en bytes (après décompression).
    func didReceiveMessage(topic: RealtimeTopic, latency: TimeInterval?, size: Int)

    /// Un message a été publié avec succès.
    ///
    /// - Parameters:
    ///   - topic: Le topic de destination.
    ///   - qos: Le QoS utilisé.
    ///   - latency: Temps entre l'appel publish et la confirmation (QoS 1+).
    func didPublishMessage(topic: RealtimeTopic, qos: RealtimeQoS, latency: TimeInterval?)

    /// Un message a été perdu ou droppé.
    ///
    /// - Parameters:
    ///   - topic: Le topic concerné.
    ///   - reason: La raison de la perte.
    func didLoseMessage(topic: RealtimeTopic, reason: MessageLossReason)

    /// Un message dupliqué a été filtré par le MessageDeduplicator.
    ///
    /// - Parameters:
    ///   - topic: Le topic concerné.
    ///   - messageId: L'ID du message dupliqué.
    func didDeduplicateMessage(topic: RealtimeTopic, messageId: MessageID)

    // MARK: - Connection

    /// L'état de connexion a changé.
    ///
    /// - Parameters:
    ///   - from: L'état précédent.
    ///   - to: Le nouvel état.
    func didChangeConnectionState(
        from: RealtimeConnectionState,
        to: RealtimeConnectionState
    )

    /// Une reconnexion a réussi.
    ///
    /// - Parameters:
    ///   - attempt: Numéro de la tentative qui a réussi.
    ///   - transport: Nom du transport utilisé (ex: "MQTT", "WebSocket").
    ///   - duration: Temps total passé en reconnexion.
    func didReconnect(attempt: Int, transport: String, duration: TimeInterval)

    /// Un fallback de transport a eu lieu.
    ///
    /// - Parameters:
    ///   - from: Transport qui a échoué.
    ///   - to: Transport de fallback.
    ///   - reason: Raison du fallback.
    func didFallbackTransport(from: String, to: String, reason: String)

    // MARK: - Offline Queue

    /// La file hors ligne a été vidée à la reconnexion.
    ///
    /// - Parameters:
    ///   - messageCount: Nombre de messages envoyés.
    ///   - expiredCount: Nombre de messages purgés (TTL expiré).
    ///   - duration: Temps pour vider la file.
    func didFlushOfflineQueue(messageCount: Int, expiredCount: Int, duration: TimeInterval)

    // MARK: - Subscriptions

    /// Le nombre de souscriptions actives a changé.
    ///
    /// - Parameters:
    ///   - activeCount: Nombre actuel de souscriptions.
    ///   - event: Ajout ou suppression.
    func didChangeSubscriptionCount(activeCount: Int, event: SubscriptionEvent)

    // MARK: - Performance

    /// Snapshot périodique des performances temps réel.
    ///
    /// Émis à intervalles réguliers (ex: toutes les 60s) pour le monitoring continu.
    func didCollectPerformanceSnapshot(_ snapshot: RealtimePerformanceSnapshot)
}

// MARK: - Default Implementations (no-op)

extension RealtimeMetricsDelegate {
    public func didReceiveMessage(topic: RealtimeTopic, latency: TimeInterval?, size: Int) {}
    public func didPublishMessage(topic: RealtimeTopic, qos: RealtimeQoS, latency: TimeInterval?) {}
    public func didLoseMessage(topic: RealtimeTopic, reason: MessageLossReason) {}
    public func didDeduplicateMessage(topic: RealtimeTopic, messageId: MessageID) {}
    public func didChangeConnectionState(from: RealtimeConnectionState, to: RealtimeConnectionState) {}
    public func didReconnect(attempt: Int, transport: String, duration: TimeInterval) {}
    public func didFallbackTransport(from: String, to: String, reason: String) {}
    public func didFlushOfflineQueue(messageCount: Int, expiredCount: Int, duration: TimeInterval) {}
    public func didChangeSubscriptionCount(activeCount: Int, event: SubscriptionEvent) {}
    public func didCollectPerformanceSnapshot(_ snapshot: RealtimePerformanceSnapshot) {}
}

// MARK: - Supporting Types

/// Raison de la perte d'un message.
public enum MessageLossReason: Sendable, Equatable, CustomStringConvertible {
    /// Le message a été droppé par la backpressure (buffer plein).
    case backpressure(topic: String, bufferSize: Int)

    /// Le message a été droppé pendant un changement de transport (fallback).
    case transportSwitch

    /// Le message n'a pas pu être décodé (payload corrompu).
    case decodingFailure(topic: String)

    /// Le message a expiré dans l'offline queue (TTL dépassé).
    case ttlExpired(topic: String, age: TimeInterval)

    /// Le message a été rejeté par le broker (ACL, quota).
    case serverRejected(topic: String, reason: String)

    public var description: String {
        switch self {
        case .backpressure(let topic, let size):
            return "backpressure on \(topic) (buffer: \(size))"
        case .transportSwitch:
            return "transport switch"
        case .decodingFailure(let topic):
            return "decoding failure on \(topic)"
        case .ttlExpired(let topic, let age):
            return "TTL expired on \(topic) (age: \(Int(age))s)"
        case .serverRejected(let topic, let reason):
            return "server rejected on \(topic): \(reason)"
        }
    }
}

/// Événement de changement de souscription.
public enum SubscriptionEvent: Sendable, Equatable, CustomStringConvertible {
    case added(topic: RealtimeTopic)
    case removed(topic: RealtimeTopic)
    case cancelledAll(feature: String)

    public var description: String {
        switch self {
        case .added(let topic):
            return "added(\(topic.path))"
        case .removed(let topic):
            return "removed(\(topic.path))"
        case .cancelledAll(let feature):
            return "cancelledAll(\(feature))"
        }
    }
}

/// Snapshot périodique des performances temps réel.
public struct RealtimePerformanceSnapshot: Sendable {

    /// Nombre total de messages reçus depuis le dernier snapshot.
    public let messagesReceived: Int

    /// Nombre total de messages publiés depuis le dernier snapshot.
    public let messagesPublished: Int

    /// Latence moyenne de réception (ms).
    public let averageReceiveLatencyMs: Double?

    /// Latence moyenne de publication (ms) — QoS 1+ uniquement.
    public let averagePublishLatencyMs: Double?

    /// Nombre de messages dédupliqués.
    public let duplicatesFiltered: Int

    /// Nombre de reconnexions.
    public let reconnectionCount: Int

    /// Nombre de souscriptions actives.
    public let activeSubscriptions: Int

    /// Taille courante de la file hors ligne.
    public let offlineQueueSize: Int

    /// Durée de la période couverte par ce snapshot.
    public let periodSeconds: TimeInterval

    public init(
        messagesReceived: Int,
        messagesPublished: Int,
        averageReceiveLatencyMs: Double?,
        averagePublishLatencyMs: Double?,
        duplicatesFiltered: Int,
        reconnectionCount: Int,
        activeSubscriptions: Int,
        offlineQueueSize: Int,
        periodSeconds: TimeInterval
    ) {
        self.messagesReceived = messagesReceived
        self.messagesPublished = messagesPublished
        self.averageReceiveLatencyMs = averageReceiveLatencyMs
        self.averagePublishLatencyMs = averagePublishLatencyMs
        self.duplicatesFiltered = duplicatesFiltered
        self.reconnectionCount = reconnectionCount
        self.activeSubscriptions = activeSubscriptions
        self.offlineQueueSize = offlineQueueSize
        self.periodSeconds = periodSeconds
    }
}
