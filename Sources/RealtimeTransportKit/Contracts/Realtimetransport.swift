//
//  Realtimetransport.swift
//  AppModules
//
//  Created by Asyst on 6/2/26.
//

// MARK: - RealtimeKit/Contracts/RealtimeTransport.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Protocol interne que chaque transport implémente.
//           Équivalent de DatabaseEngine dans StorageKit.
//
// Design  : Le RealtimeTransport travaille avec des données brutes (Data).
//           L'encodage/décodage typé est géré par le RealtimeClient (adapter).
//           Chaque transport est un actor pour le thread safety (Swift 6).
//
//           RealtimeClientProtocol (CoreKit)    →  typé, public, features
//           RealtimeTransport (RealtimeKit)     →  raw Data, internal, transports
//
//           C'est le même pattern que :
//           DatabaseRepositoryProtocol (CoreKit) → typé, public, features
//           DatabaseEngine (StorageKit)          → raw SQL/CoreData, internal, engines
//
// Implémentations :
//   - MQTTTransport      → CocoaMQTT
//   - WebSocketTransport → Starscream / URLSessionWebSocketTask
//   - InMemoryTransport  → tests unitaires
//
// Contrainte Swift 6 :
//   Les closures sync de CocoaMQTT/Starscream ne peuvent pas appeler des méthodes
//   actor-isolated. Les transports utilisent des méthodes statiques + nonisolated
//   pour les callbacks des libs externes (même pattern que SQLiteEngine avec GRDB).

import Foundation
import WaanguCoreKit

// MARK: - RealtimeTransport

/// Protocol interne implémenté par chaque transport (MQTT, WebSocket, InMemory).
///
/// Le `RealtimeClient` (adapter central) détient un `any RealtimeTransport`
/// et lui délègue les opérations réseau brutes. Le transport ne connaît pas
/// les types métier — il envoie et reçoit du `Data`.
///
/// Chaque implémentation est un `actor` pour garantir le thread safety.
protocol RealtimeTransport: Sendable {

    // MARK: - Identity

    /// Nom du transport pour le logging et les métriques.
    /// Ex: "MQTT", "WebSocket", "InMemory".
    var transportName: String { get }

    /// Type de transport (pour le fallback chain et la configuration).
    var transportType: RealtimeTransportType { get }

    // MARK: - Connection Lifecycle

    /// Établit la connexion au broker/serveur.
    ///
    /// L'implémentation doit :
    /// 1. Établir la connexion TCP/TLS
    /// 2. Effectuer le handshake du protocole (MQTT CONNECT, WS Upgrade)
    /// 3. S'authentifier avec les credentials de la config
    /// 4. Émettre `.connected` sur le state stream
    ///
    /// - Parameter config: Configuration complète du transport.
    /// - Throws: Erreur de connexion (mappée vers `RealtimeError` par le client).
    func connect(config: RealtimeTransportConfig) async throws

    /// Ferme la connexion proprement.
    ///
    /// L'implémentation doit :
    /// 1. Envoyer le message de fermeture du protocole (MQTT DISCONNECT, WS Close)
    /// 2. Fermer la connexion TCP
    /// 3. Émettre `.disconnected` sur le state stream
    /// 4. Terminer tous les streams actifs
    ///
    /// - Parameter reason: Raison de la déconnexion (pour le Last Will / Close reason).
    func disconnect(reason: DisconnectReason) async throws

    /// `true` si le transport est actuellement connecté et prêt.
    var isConnected: Bool { get async }

    // MARK: - Connection State

    /// Stream des changements d'état de la connexion au niveau transport.
    ///
    /// Le `RealtimeClient` observe ce stream et le propage vers les features
    /// via `observeConnectionState()`.
    ///
    /// Le transport émet les états bruts. Le `RealtimeClient` peut enrichir
    /// (ex: ajouter l'état `.authenticating` entre `.connecting` et `.connected`).
    func connectionStateStream() async -> AsyncStream<TransportConnectionEvent>

    // MARK: - Subscribe / Unsubscribe

    /// Souscrit à un topic sur le broker.
    ///
    /// - Parameters:
    ///   - topic: Le chemin du topic (string brut, déjà résolu par le client).
    ///   - qos: Le QoS demandé (traduit en QoS natif du protocole).
    /// - Throws: Erreur de souscription (broker reject, ACL, etc.).
    func subscribe(topic: String, qos: RealtimeQoS) async throws

    /// Se désabonne d'un topic.
    ///
    /// - Parameter topic: Le chemin du topic à quitter.
    /// - Throws: Erreur de désabonnement.
    func unsubscribe(topic: String) async throws

    // MARK: - Publish

    /// Publie des données brutes sur un topic.
    ///
    /// Le payload est déjà encodé en Data par le `RealtimeClient`.
    /// Le transport l'envoie tel quel.
    ///
    /// - Parameters:
    ///   - data: Le payload encodé (JSON Data).
    ///   - topic: Le topic de destination.
    ///   - qos: Le QoS demandé.
    ///   - messageId: L'ID du message (pour le tracking QoS 1/2).
    /// - Throws: Erreur de publication.
    func publish(
        data: Data,
        to topic: String,
        qos: RealtimeQoS,
        messageId: MessageID
    ) async throws

    // MARK: - Receive

    /// Stream des messages bruts reçus du broker.
    ///
    /// Le `RealtimeClient` consomme ce stream, décode les payloads,
    /// déduplique, et dispatch vers les souscriptions typées des features.
    ///
    /// Le stream ne se termine jamais tant que le transport est connecté.
    /// À la déconnexion, le stream émet un finish.
    func incomingMessages() async -> AsyncStream<RawTransportMessage>

    // MARK: - Heartbeat / Keep-alive

    /// Met à jour l'intervalle de heartbeat/keep-alive.
    ///
    /// Appelé par le `BatteryAwareScheduler` quand l'app passe en
    /// foreground/background ou quand les conditions changent.
    ///
    /// - Parameter interval: Nouvel intervalle en secondes.
    ///                       `nil` = utiliser le défaut du transport.
    func updateHeartbeatInterval(_ interval: TimeInterval?) async

    // MARK: - Re-authentication

    /// Met à jour les credentials sur une connexion existante.
    ///
    /// Utilisé pour le token refresh sans déconnexion.
    /// Tous les transports ne supportent pas ça nativement :
    /// - MQTT 5 : via AUTH packet
    /// - WebSocket : via message d'auth applicatif
    /// - MQTT 3.1.1 : non supporté → reconnexion nécessaire
    ///
    /// - Parameter credentials: Les nouveaux credentials.
    /// - Returns: `true` si le re-auth a été fait in-place.
    ///            `false` si une reconnexion est nécessaire.
    @discardableResult
    func reauthenticate(with credentials: RealtimeCredentials) async throws -> Bool
}

// MARK: - Default Implementations

extension RealtimeTransport {

    /// Par défaut, le re-auth nécessite une reconnexion.
    /// Les transports qui supportent le re-auth in-place override cette méthode.
    func reauthenticate(with credentials: RealtimeCredentials) async throws -> Bool {
        return false
    }

    /// Par défaut, utilise le heartbeat de la config initiale.
    func updateHeartbeatInterval(_ interval: TimeInterval?) async {
        // No-op par défaut — les transports qui supportent le heartbeat
        // dynamique (MQTT keep-alive, WS ping interval) overrident.
    }
}

// MARK: - RawTransportMessage

/// Message brut reçu par le transport avant décodage.
///
/// Le `RealtimeClient` transforme ça en `RealtimeMessage<T>` typé
/// via le `PayloadDecoder`.
struct RawTransportMessage: Sendable {

    /// Topic d'origine (string brut du broker).
    let topic: String

    /// Payload brut (JSON Data non décodé).
    let payload: Data

    /// QoS avec lequel le message a été reçu.
    let qos: RealtimeQoS

    /// ID du message côté broker (si disponible).
    /// Utilisé pour la déduplication et le QoS 2 handshake.
    let brokerMessageId: String?

    /// Timestamp de réception locale (pour le calcul de latence).
    let receivedAt: Date

    /// `true` si le broker indique que c'est un message retenu (MQTT retained).
    let isRetained: Bool

    /// Properties additionnelles du protocole (MQTT 5 user properties, WS headers).
    let properties: [String: String]

    // MARK: - Init

    init(
        topic: String,
        payload: Data,
        qos: RealtimeQoS = .fireAndForget,
        brokerMessageId: String? = nil,
        receivedAt: Date = Date(),
        isRetained: Bool = false,
        properties: [String: String] = [:]
    ) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.brokerMessageId = brokerMessageId
        self.receivedAt = receivedAt
        self.isRetained = isRetained
        self.properties = properties
    }
}

// MARK: - TransportConnectionEvent

/// Événement de connexion émis par un transport.
///
/// Plus granulaire que `RealtimeConnectionState` (CoreKit) car il inclut
/// des détails spécifiques au transport que le client filtre/enrichit.
enum TransportConnectionEvent: Sendable {

    /// La connexion TCP/TLS est en cours.
    case connecting

    /// La connexion TCP est établie, handshake protocole en cours.
    case handshaking

    /// Le transport est connecté et prêt.
    case connected

    /// La connexion a été perdue.
    /// - `error`: L'erreur sous-jacente (spécifique au transport).
    /// - `isRecoverable`: `true` si le ReconnectionManager devrait retenter.
    case disconnected(error: String?, isRecoverable: Bool)

    /// Le broker a envoyé un signal de fermeture propre.
    /// - `code`: Code de fermeture du protocole (MQTT reason code, WS close code).
    /// - `reason`: Message de fermeture (si disponible).
    case serverDisconnect(code: Int?, reason: String?)

    /// Le transport a détecté un timeout de heartbeat/keep-alive.
    /// Le `ReconnectionManager` devrait déclencher une reconnexion.
    case heartbeatTimeout

    /// Le broker a rejeté l'authentification.
    case authenticationRejected(reason: String)
}

// MARK: - TransportConnectionEvent Helpers

extension TransportConnectionEvent {

    /// `true` si cet événement indique que le transport est fonctionnel.
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// `true` si cet événement devrait déclencher une tentative de reconnexion.
    var shouldReconnect: Bool {
        switch self {
        case .disconnected(_, let isRecoverable):
            return isRecoverable
        case .heartbeatTimeout:
            return true
        case .serverDisconnect:
            return true
        default:
            return false
        }
    }

    /// `true` si cet événement est une erreur d'authentification
    /// (pas de reconnexion — il faut un nouveau token).
    var isAuthError: Bool {
        if case .authenticationRejected = self { return true }
        return false
    }

    /// Convertit vers un `RealtimeConnectionState` pour le CoreKit.
    ///
    /// Le `RealtimeClient` utilise ça pour propager l'état vers les features.
    /// Certains états sont enrichis par le client (ex: `.reconnecting` avec le compteur).
    func toConnectionState() -> RealtimeConnectionState? {
        switch self {
        case .connecting, .handshaking:
            return .connecting
        case .connected:
            return .connected
        case .disconnected(_, _):
            return .disconnected(reason: .serverClosed(code: nil))
        case .serverDisconnect(let code, _):
            return .disconnected(reason: .serverClosed(code: code))
        case .heartbeatTimeout:
            return .disconnected(reason: .networkLost)
        case .authenticationRejected:
            return .disconnected(reason: .tokenExpired)
        }
    }
}

// MARK: - RealtimeTransportType

/// Type de transport disponible.
///
/// Utilisé dans la configuration, le fallback chain, et les métriques.
enum RealtimeTransportType: String, Sendable, CaseIterable {

    /// MQTT via CocoaMQTT (protocole binaire, optimisé IoT).
    case mqtt = "MQTT"

    /// WebSocket via Starscream ou URLSessionWebSocketTask.
    case webSocket = "WebSocket"

    /// Server-Sent Events (unidirectionnel serveur → client).
    case sse = "SSE"

    /// Transport en mémoire pour les tests unitaires.
    case inMemory = "InMemory"
}
