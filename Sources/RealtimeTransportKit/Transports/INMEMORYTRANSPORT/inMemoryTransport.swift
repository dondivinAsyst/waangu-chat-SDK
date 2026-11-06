// MARK: - RealtimeKit/Transports/InMemoryTransport.swift
//
// Module  : RealtimeKit (internal, exposed via RealtimeAssembly.makeInMemory)
// Rôle    : Transport déterministe pour les tests unitaires.
//           Pas de réseau, pas de broker — tout est en mémoire.
//           Permet de simuler des messages entrants, des déconnexions,
//           et de vérifier les messages publiés.
//
// Design  : Actor pour la cohérence avec les vrais transports.
//           Expose des méthodes `simulate*` pour les tests.
//
// Usage dans les tests :
//   let (client, transport) = RealtimeAssembly.makeInMemory()
//   try await client.connect()
//
//   // Simuler un message entrant du broker :
//   await transport.simulateIncoming(topic: "chat/1/messages", payload: data)
//
//   // Vérifier les messages publiés :
//   let published = await transport.publishedMessages
//   XCTAssertEqual(published.count, 1)

import Foundation
import WaanguCoreKit

// MARK: - InMemoryTransport

/// Transport en mémoire pour les tests unitaires.
///
/// ```swift
/// let (client, transport) = RealtimeAssembly.makeInMemory()
/// try await client.connect()
///
/// // Souscrire
/// let (stream, token) = try await client.subscribe(
///     to: .scoped(feature: "chat", path: "1/messages"),
///     as: ChatMessage.self
/// )
///
/// // Simuler un message entrant
/// let msg = ChatMessage(id: UUID(), text: "Hello")
/// let data = try JSONEncoder().encode(msg)
/// await transport.simulateIncoming(topic: "chat/1/messages", payload: data)
///
/// // Vérifier
/// for await received in stream {
///     XCTAssertEqual(received.text, "Hello")
///     break
/// }
/// ```
public actor InMemoryTransport: RealtimeTransport {

    // MARK: - Identity

    nonisolated let transportName: String = "InMemory"
    nonisolated let transportType: RealtimeTransportType = .inMemory

    // MARK: - State

    private var _isConnected: Bool = false
    private var subscribedTopics: [String: RealtimeQoS] = [:]

    // MARK: - Streams

    private var connectionContinuation: AsyncStream<TransportConnectionEvent>.Continuation?
    private var messageContinuation: AsyncStream<RawTransportMessage>.Continuation?

    // MARK: - Recording (pour les assertions dans les tests)

    /// Tous les messages publiés par le client (pour vérification dans les tests).
    private(set) var publishedMessages: [RecordedMessage] = []

    /// Tous les topics auxquels le client s'est souscrit.
    public var activeSubscriptions: [String: RealtimeQoS] { subscribedTopics }

    /// Historique des événements de connexion émis.
    private(set) var connectionHistory: [TransportConnectionEvent] = []

    // MARK: - Init

    public init() {}

    // MARK: - RealtimeTransport — Connection

    var isConnected: Bool { _isConnected }

    func connect(config: RealtimeTransportConfig) async throws {
        _isConnected = true
        let event = TransportConnectionEvent.connected
        connectionContinuation?.yield(event)
        connectionHistory.append(event)
    }

    func disconnect(reason: DisconnectReason) async throws {
        _isConnected = false
        subscribedTopics.removeAll()
        let event = TransportConnectionEvent.disconnected(error: nil, isRecoverable: false)
        connectionContinuation?.yield(event)
        connectionHistory.append(event)
    }

    func connectionStateStream() async -> AsyncStream<TransportConnectionEvent> {
        connectionContinuation?.finish()
        let (stream, continuation) = AsyncStream<TransportConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(20)
        )
        connectionContinuation = continuation
        return stream
    }

    // MARK: - RealtimeTransport — Subscribe / Unsubscribe

    func subscribe(topic: String, qos: RealtimeQoS) async throws {
        guard _isConnected else { throw RealtimeError.notConnected }
        subscribedTopics[topic] = qos
    }

    func unsubscribe(topic: String) async throws {
        subscribedTopics.removeValue(forKey: topic)
    }

    // MARK: - RealtimeTransport — Publish

    func publish(
        data: Data,
        to topic: String,
        qos: RealtimeQoS,
        messageId: MessageID
    ) async throws {
        guard _isConnected else { throw RealtimeError.notConnected }

        publishedMessages.append(RecordedMessage(
            topic: topic,
            data: data,
            qos: qos,
            messageId: messageId,
            timestamp: Date()
        ))
    }

    // MARK: - RealtimeTransport — Incoming Messages

    func incomingMessages() async -> AsyncStream<RawTransportMessage> {
        messageContinuation?.finish()
        let (stream, continuation) = AsyncStream<RawTransportMessage>.makeStream(
            bufferingPolicy: .bufferingNewest(100)
        )
        messageContinuation = continuation
        return stream
    }

    // MARK: - RealtimeTransport — Heartbeat / Reauth

    func updateHeartbeatInterval(_ interval: TimeInterval?) async {}

    func reauthenticate(with credentials: RealtimeCredentials) async throws -> Bool {
        return true  // InMemory supporte toujours le re-auth.
    }

    // =========================================================================
    // MARK: - Test Simulation API
    // =========================================================================

    /// Simule un message entrant (comme si le broker l'envoyait).
    ///
    /// ```swift
    /// let data = try JSONEncoder().encode(ChatMessage(text: "Hello"))
    /// await transport.simulateIncoming(topic: "chat/1/messages", payload: data)
    /// ```
    public func simulateIncoming(
        topic: String,
        payload: Data,
        qos: RealtimeQoS = .atLeastOnce,
        messageId: String? = nil,
        retained: Bool = false,
        properties: [String: String] = [:]
    ) {
        let raw = RawTransportMessage(
            topic: topic,
            payload: payload,
            qos: qos,
            brokerMessageId: messageId ?? UUID().uuidString,
            receivedAt: Date(),
            isRetained: retained,
            properties: properties
        )
        messageContinuation?.yield(raw)
    }

    /// Simule une déconnexion inattendue (perte réseau).
    public func simulateDisconnection(recoverable: Bool = true) {
        _isConnected = false
        let event = TransportConnectionEvent.disconnected(
            error: "Simulated disconnection",
            isRecoverable: recoverable
        )
        connectionContinuation?.yield(event)
        connectionHistory.append(event)
    }

    /// Simule un timeout de heartbeat.
    public func simulateHeartbeatTimeout() {
        let event = TransportConnectionEvent.heartbeatTimeout
        connectionContinuation?.yield(event)
        connectionHistory.append(event)
    }

    /// Simule un rejet d'authentification par le broker.
    public func simulateAuthRejection(reason: String = "Token expired") {
        let event = TransportConnectionEvent.authenticationRejected(reason: reason)
        connectionContinuation?.yield(event)
        connectionHistory.append(event)
    }

    /// Simule une déconnexion initiée par le serveur.
    public func simulateServerDisconnect(code: Int? = nil, reason: String? = nil) {
        _isConnected = false
        let event = TransportConnectionEvent.serverDisconnect(code: code, reason: reason)
        connectionContinuation?.yield(event)
        connectionHistory.append(event)
    }

    /// Vide l'historique des messages publiés et des événements.
    public func resetRecording() {
        publishedMessages.removeAll()
        connectionHistory.removeAll()
    }

    /// Le dernier message publié (raccourci pour les tests simples).
    public var lastPublishedMessage: RecordedMessage? {
        publishedMessages.last
    }
}

// MARK: - RecordedMessage

/// Message enregistré par l'InMemoryTransport pour les assertions de test.
public struct RecordedMessage: Sendable {
    public let topic: String
    public let data: Data
    public let qos: RealtimeQoS
    public let messageId: MessageID
    public let timestamp: Date

    /// Décode le payload pour les assertions typées.
    public func decode<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
