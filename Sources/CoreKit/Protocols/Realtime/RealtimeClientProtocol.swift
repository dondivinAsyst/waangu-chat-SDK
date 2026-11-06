// MARK: - CoreKit/Realtime/RealtimeClientProtocol.swift
//
// Module  : CoreKit
// Rôle    : Contrat principal du système temps réel.
//           Équivalent de DatabaseRepositoryProtocol pour la database.
//           Les features importent UNIQUEMENT CoreKit et reçoivent ce protocol
//           via injection (struct Dependencies).
//
// Design  : Le protocol couvre les 5 responsabilités fondamentales :
//           1. Connection lifecycle (connect, disconnect, observe state)
//           2. Pub/Sub (subscribe, publish)
//           3. Request-Reply (request avec corrélation et timeout)
//           4. Presence (publish state, observe others)
//           5. Subscription management (cancel, cleanup, count)
//
// Implémentation : RealtimeClient (actor) dans RealtimeKit.
//                  Les features ne savent JAMAIS si c'est MQTT, WebSocket, ou InMemory.
//
// Injection :
//   struct ChatDependencies {
//       let realtime: any RealtimeClientProtocol   // ← injecté par DependencyContainer
//       let database: any DatabaseRepositoryProtocol
//   }

import Foundation

// MARK: - RealtimeClientProtocol

/// Contrat principal du système de communication temps réel.
///
/// Les features interagissent exclusivement avec ce protocol.
/// Le transport sous-jacent (MQTT, WebSocket, etc.) est invisible.
///
/// ## Usage typique
///
/// ```swift
/// // FeatureChat — import CoreKit uniquement
/// actor ChatRepository {
///     private let realtime: any RealtimeClientProtocol
///     private let subscriptions = SubscriptionGroup()
///
///     func observeMessages(conversationId: String) async throws -> AsyncStream<ChatMessage> {
///         let (stream, token) = try await realtime.subscribe(
///             to: .scoped(feature: "chat", path: "\(conversationId)/messages"),
///             as: ChatMessage.self,
///             buffering: .unbounded,
///             qos: .atLeastOnce
///         )
///         subscriptions.add(token)
///         return stream
///     }
///
///     func sendMessage(_ msg: ChatMessage) async throws {
///         try await realtime.publish(
///             msg,
///             to: .scoped(feature: "chat", path: "\(msg.conversationId)/messages"),
///             qos: .atLeastOnce,
///             priority: .normal
///         )
///     }
///
///     func cleanup() async { await subscriptions.cancelAll() }
/// }
/// ```
public protocol RealtimeClientProtocol: Sendable {

    // MARK: - Connection Lifecycle

    /// État courant de la connexion.
    var connectionState: RealtimeConnectionState { get async }

    /// Observe les changements d'état de la connexion.
    ///
    /// L'AsyncStream émet chaque transition. Les features utilisent ça
    /// pour afficher un banner "reconnexion...", désactiver des boutons, etc.
    ///
    /// Le stream ne se termine jamais tant que le client existe.
    func observeConnectionState() -> AsyncStream<RealtimeConnectionState>

    /// Établit la connexion au broker.
    ///
    /// - L'authentification est gérée via le `RealtimeAuthDelegate`.
    /// - Si un fallback chain est configuré, les transports sont essayés dans l'ordre.
    /// - L'appel retourne quand l'état passe à `.connected`.
    ///
    /// - Throws: `RealtimeError.connectionFailed`, `.authenticationFailed`,
    ///           `.allTransportsFailed`, `.invalidConfiguration`.
    func connect() async throws

    /// Déconnexion propre.
    ///
    /// 1. Flush la offline queue si `flushQueue` est `true` (envoyer les messages pendants)
    /// 2. Annule toutes les souscriptions actives
    /// 3. Envoie un Last Will / close frame au broker
    /// 4. Passe en `.disconnected(reason:)`
    ///
    /// - Parameters:
    ///   - reason: Raison de la déconnexion (pour les métriques et le logging).
    ///   - flushQueue: Si `true`, tente d'envoyer les messages en offline queue avant de couper.
    func disconnect(reason: DisconnectReason, flushQueue: Bool) async throws

    // MARK: - Subscribe

    /// Souscrit à un topic et reçoit les messages typés via un AsyncStream.
    ///
    /// Le type `T` est décodé automatiquement par le PayloadDecoder interne.
    /// Le `RealtimeSubscriptionToken` retourné contrôle le lifecycle :
    /// appeler `token.cancel()` ou laisser le token mourir met fin au stream.
    ///
    /// - Parameters:
    ///   - topic: Le topic à écouter.
    ///   - type: Le type Swift attendu pour le payload (doit être Decodable & Sendable).
    ///   - buffering: Stratégie de backpressure pour ce stream.
    ///   - qos: Qualité de service pour cette souscription.
    /// - Returns: Un tuple (stream, token). Le stream émet les messages,
    ///            le token contrôle le lifecycle.
    /// - Throws: `RealtimeError.notConnected`, `.subscriptionDenied`,
    ///           `.subscriptionLimitReached`.
    func subscribe<T: Decodable & Sendable>(
        to topic: RealtimeTopic,
        as type: T.Type,
        buffering: RealtimeBufferingPolicy,
        qos: RealtimeQoS
    ) async throws -> (stream: AsyncStream<T>, token: any RealtimeSubscriptionToken)

    // MARK: - Publish

    /// Publie un message typé sur un topic.
    ///
    /// Le payload est encodé automatiquement en JSON.
    /// Si le client est déconnecté et qu'une offline queue est configurée,
    /// le message est mis en file (et `RealtimeError.reconnecting` n'est PAS thrown —
    /// le message partira à la reconnexion).
    ///
    /// - Parameters:
    ///   - payload: Le message à envoyer (doit être Encodable & Sendable).
    ///   - topic: Le topic de destination.
    ///   - qos: Qualité de service pour cet envoi.
    ///   - priority: Priorité du message.
    /// - Throws: `RealtimeError.notConnected` (si pas d'offline queue),
    ///           `.publishFailed`, `.payloadTooLarge`, `.encodingFailed`.
    func publish<T: Encodable & Sendable>(
        _ payload: T,
        to topic: RealtimeTopic,
        qos: RealtimeQoS,
        priority: MessagePriority
    ) async throws

    // MARK: - Request-Reply

    /// Envoie une requête et attend une réponse corrélée.
    ///
    /// Publie le payload sur `topic`, puis attend un message sur `replyOn`
    /// dont le `correlationId` correspond. Timeout si pas de réponse.
    ///
    /// Usage typique : envoyer un message chat et attendre l'accusé serveur.
    ///
    /// ```swift
    /// let ack = try await realtime.request(
    ///     message,
    ///     to: .scoped(feature: "chat", path: "\(convId)/messages"),
    ///     replyOn: .scoped(feature: "chat", path: "\(convId)/acks"),
    ///     as: ServerAck.self,
    ///     timeout: 10.0
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - payload: La requête à envoyer.
    ///   - topic: Le topic de publication de la requête.
    ///   - replyOn: Le topic sur lequel la réponse est attendue.
    ///   - responseType: Le type Swift de la réponse.
    ///   - timeout: Durée max d'attente (en secondes).
    /// - Returns: La réponse décodée.
    /// - Throws: `RealtimeError.requestTimeout`, `.notConnected`,
    ///           `.encodingFailed`, `.decodingFailed`.
    func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ payload: Request,
        to topic: RealtimeTopic,
        replyOn: RealtimeTopic,
        as responseType: Response.Type,
        timeout: TimeInterval
    ) async throws -> Response

    // MARK: - Presence

    /// Publie un état de presence sur un topic.
    ///
    /// ```swift
    /// try await realtime.publishPresence(
    ///     .typing(in: conversationId),
    ///     to: .scoped(feature: "chat", path: "\(conversationId)/presence")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - state: L'état de presence à publier.
    ///   - topic: Le topic de presence.
    /// - Throws: `RealtimeError.notConnected`, `.publishFailed`.
    func publishPresence(
        _ state: PresenceState,
        to topic: RealtimeTopic
    ) async throws

    /// Observe les changements de presence d'autres utilisateurs sur un topic.
    ///
    /// ```swift
    /// for await presence in realtime.observePresence(on: presenceTopic) {
    ///     if presence.isTyping { showTypingIndicator(for: presence.userId) }
    /// }
    /// ```
    ///
    /// - Parameter topic: Le topic de presence à observer.
    /// - Returns: Un stream de PresenceInfo (un événement par changement d'état).
    func observePresence(
        on topic: RealtimeTopic
    ) -> AsyncStream<PresenceInfo>

    // MARK: - Subscription Management

    /// Annule une souscription spécifique.
    ///
    /// Équivalent à `token.cancel()` mais depuis le client directement.
    /// Idempotent — annuler un token déjà annulé est safe.
    func cancelSubscription(_ token: any RealtimeSubscriptionToken) async

    /// Annule toutes les souscriptions d'une feature.
    ///
    /// Identifie les souscriptions par le `feature` du token (déduit du topic scoped).
    /// Utile dans le `deinit` ou `cleanup()` d'un repository.
    ///
    /// - Parameter feature: L'identifiant de la feature (ex: "chat", "ride").
    func cancelAllSubscriptions(forFeature feature: String) async

    /// Nombre de souscriptions actuellement actives.
    var activeSubscriptionCount: Int { get async }

    /// `true` si une souscription active existe actuellement pour ce topic.
    ///
    /// Destiné au monitoring/diagnostic (ex: indicateur de heartbeat dans l'UI)
    /// pour vérifier qu'on est toujours abonné à un topic donné.
    func isSubscribed(to topic: RealtimeTopic) async -> Bool

    /// Snapshot diagnostic de toutes les souscriptions actives, par topic.
    ///
    /// Destiné à un écran de monitoring : permet de voir quels topics sont
    /// abonnés et combien de souscripteurs partagent chaque topic
    /// (`subscriberCount > 1` explique la double réception d'un même payload).
    func subscriptionDiagnostics() async -> [RealtimeSubscriptionDiagnostic]

    // MARK: - Topic Registration

    /// Enregistre les topics déclarés par une feature.
    ///
    /// Appelé au bootstrap par le DependencyContainer.
    /// Les registrations sont utilisées par le BackgroundPolicyManager
    /// et l'AdaptiveRealtimePolicy.
    ///
    /// - Parameter registrations: Les déclarations de topics de la feature.
    func register(_ registrations: [TopicRegistration]) async

    // MARK: - Offline Queue

    /// Accès à la file d'attente hors ligne.
    ///
    /// Permet aux features de consulter l'état de la file
    /// (nombre de messages pendants, purge manuelle, etc.).
    var offlineQueue: any OfflineQueueProtocol { get }
}

// MARK: - RealtimeSubscriptionDiagnostic

/// Instantané diagnostic d'un topic abonné, pour les écrans de monitoring.
public struct RealtimeSubscriptionDiagnostic: Sendable, Identifiable, Hashable {

    /// Le chemin du topic (ex: `"waangu-chat/123"`).
    public let topicPath: String

    /// Nombre de souscriptions locales partageant ce topic.
    /// `> 1` signifie que chaque payload entrant est dispatché plusieurs fois.
    public let subscriberCount: Int

    /// Le QoS le plus élevé parmi les souscriptions de ce topic.
    public let qos: RealtimeQoS

    /// `true` si le topic contient un wildcard (`+` ou `#`).
    public let isWildcard: Bool

    /// La feature propriétaire, si le topic est scopé.
    public let feature: String?

    public var id: String { topicPath }

    public init(
        topicPath: String,
        subscriberCount: Int,
        qos: RealtimeQoS,
        isWildcard: Bool,
        feature: String?
    ) {
        self.topicPath = topicPath
        self.subscriberCount = subscriberCount
        self.qos = qos
        self.isWildcard = isWildcard
        self.feature = feature
    }
}

// MARK: - Convenience Defaults

/// Valeurs par défaut pour les paramètres optionnels.
///
/// Permet aux features d'appeler les méthodes avec moins de paramètres
/// dans les cas courants.
extension RealtimeClientProtocol {

    /// Subscribe avec les defaults : buffering unbounded, QoS atLeastOnce.
    public func subscribe<T: Decodable & Sendable>(
        to topic: RealtimeTopic,
        as type: T.Type
    ) async throws -> (stream: AsyncStream<T>, token: any RealtimeSubscriptionToken) {
        try await subscribe(
            to: topic,
            as: type,
            buffering: .default,
            qos: .atLeastOnce
        )
    }

    /// Publish avec les defaults : QoS atLeastOnce, priority normal.
    public func publish<T: Encodable & Sendable>(
        _ payload: T,
        to topic: RealtimeTopic
    ) async throws {
        try await publish(
            payload,
            to: topic,
            qos: .atLeastOnce,
            priority: .normal
        )
    }

    /// Disconnect avec les defaults : flush queue, user initiated.
    public func disconnect() async throws {
        try await disconnect(reason: .userInitiated, flushQueue: true)
    }
}
