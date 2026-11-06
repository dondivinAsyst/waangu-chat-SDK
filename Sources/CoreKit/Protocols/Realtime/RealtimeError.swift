// MARK: - CoreKit/Realtime/RealtimeError.swift
//
// Module  : CoreKit
// Rôle    : Erreurs typées pour l'infrastructure temps réel.
//           Aucune technologie — ni MQTT, ni WebSocket, ni aucun transport.
//           Les features catchent ces erreurs sans jamais connaître le transport sous-jacent.
//
// Pattern : Même approche que DatabaseError dans CoreKit/Database.
// Règle   : Toute erreur spécifique au transport est mappée vers ces cas dans RealtimeKit.

import Foundation

// MARK: - RealtimeError

/// Erreurs de l'infrastructure temps réel.
///
/// Chaque transport (MQTT, WebSocket, etc.) mappe ses erreurs natives vers ces cas.
/// Les features n'importent que CoreKit et ne voient jamais l'erreur d'origine.
public enum RealtimeError: Error, Sendable, Equatable {

    // MARK: - Connection

    /// La connexion au broker a échoué.
    /// - Parameter reason: description humaine (loggée, jamais affichée à l'utilisateur).
    case connectionFailed(reason: String)

    /// La connexion a été perdue de manière inattendue.
    case connectionLost

    /// Tous les transports de la fallback chain ont échoué.
    case allTransportsFailed

    /// Tentative d'opération alors que le client n'est pas connecté.
    case notConnected

    /// Le client est en cours de reconnexion — l'opération a été mise en file (offline queue).
    case reconnecting

    // MARK: - Authentication

    /// Les credentials fournis ont été refusés par le broker.
    case authenticationFailed(reason: String)

    /// Le token JWT a expiré pendant la session et le refresh a échoué.
    case tokenRefreshFailed(underlyingReason: String)

    // MARK: - Subscription

    /// L'abonnement à un topic a été refusé (ACL serveur, topic invalide, etc.).
    case subscriptionDenied(topic: String, reason: String)

    /// Le nombre maximum de souscriptions actives est atteint.
    case subscriptionLimitReached(current: Int, max: Int)

    /// Tentative de souscrire à un topic déjà souscrit.
    case alreadySubscribed(topic: String)

    // MARK: - Publishing

    /// La publication a échoué.
    case publishFailed(topic: String, reason: String)

    /// Le payload dépasse la taille maximale autorisée.
    case payloadTooLarge(size: Int, maxAllowed: Int)

    /// L'encodage du payload a échoué.
    case encodingFailed(type: String, underlyingDescription: String)

    // MARK: - Receiving

    /// Le décodage d'un message reçu a échoué.
    case decodingFailed(topic: String, underlyingDescription: String)

    // MARK: - Request-Reply

    /// Le timeout du pattern request-reply a expiré sans réponse.
    case requestTimeout(correlationId: String, timeout: TimeInterval)

    // MARK: - Offline Queue

    /// La file d'attente hors ligne est pleine.
    case offlineQueueFull(currentSize: Int, maxSize: Int)

    // MARK: - Configuration

    /// La configuration fournie est invalide.
    case invalidConfiguration(detail: String)

    // MARK: - Transport

    /// Erreur interne du transport, non catégorisable dans les cas ci-dessus.
    /// Le `transportName` identifie le transport (ex: "MQTT", "WebSocket") pour le logging.
    case transportError(transportName: String, description: String)
}

// MARK: - LocalizedError

extension RealtimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Realtime connection failed: \(reason)"
        case .connectionLost:
            return "Realtime connection lost unexpectedly"
        case .allTransportsFailed:
            return "All realtime transports failed to connect"
        case .notConnected:
            return "Realtime client is not connected"
        case .reconnecting:
            return "Realtime client is reconnecting — message queued"
        case .authenticationFailed(let reason):
            return "Realtime authentication failed: \(reason)"
        case .tokenRefreshFailed(let reason):
            return "Realtime token refresh failed: \(reason)"
        case .subscriptionDenied(let topic, let reason):
            return "Subscription denied for '\(topic)': \(reason)"
        case .subscriptionLimitReached(let current, let max):
            return "Subscription limit reached (\(current)/\(max))"
        case .alreadySubscribed(let topic):
            return "Already subscribed to '\(topic)'"
        case .publishFailed(let topic, let reason):
            return "Publish failed on '\(topic)': \(reason)"
        case .payloadTooLarge(let size, let max):
            return "Payload too large (\(size) bytes, max \(max))"
        case .encodingFailed(let type, let desc):
            return "Failed to encode \(type): \(desc)"
        case .decodingFailed(let topic, let desc):
            return "Failed to decode message on '\(topic)': \(desc)"
        case .requestTimeout(let id, let timeout):
            return "Request-reply timeout after \(timeout)s (correlationId: \(id))"
        case .offlineQueueFull(let current, let max):
            return "Offline queue full (\(current)/\(max))"
        case .invalidConfiguration(let detail):
            return "Invalid realtime configuration: \(detail)"
        case .transportError(let name, let desc):
            return "Transport error [\(name)]: \(desc)"
        }
    }
}

// MARK: - Categorization Helpers

extension RealtimeError {

    /// `true` si l'erreur est récupérable par reconnexion automatique.
    public var isRecoverable: Bool {
        switch self {
        case .connectionLost, .reconnecting, .connectionFailed:
            return true
        case .tokenRefreshFailed:
            return true   // le ReconnectionManager peut retenter après un nouveau token
        default:
            return false
        }
    }

    /// `true` si le message a été (ou sera) mis en offline queue.
    public var isQueued: Bool {
        switch self {
        case .reconnecting:
            return true
        default:
            return false
        }
    }
}
