// MARK: - RealtimeKit/Client/RealtimeClient.swift
//
// Module  : RealtimeKit (internal, exposed via RealtimeAssembly)
// Rôle    : Adapter central — implémente RealtimeClientProtocol (CoreKit)
//           et délègue au RealtimeTransport (interne).
//           Équivalent de DatabaseStore dans StorageKit.
//
// Design  : Actor pour le thread safety (Swift 6 strict concurrency).
//           Orchestre tous les sous-systèmes :
//           - ConnectionStateMachine  → transitions d'état
//           - SubscriptionRegistry    → tracking des souscriptions actives
//           - MessageDeduplicator     → filtrage des doublons entrants (QoS 1)
//           - OfflineMessageQueue     → file FIFO hors ligne
//           - PayloadDecoder          → décodage JSON centralisé
//           - PayloadCompressor       → compression/décompression
//           - RealtimeTokenRefresher  → refresh proactif du JWT
//
//           Le RealtimeClient fait le pont entre :
//           - Le monde typé des features (generics, RealtimeTopic, CoreKit)
//           - Le monde brut du transport (Data, String, RawTransportMessage)
//
// Cycle de vie :
//   1. Créé par RealtimeAssembly.make() avec toutes ses dépendances
//   2. connect() → transport + auth + receive loop
//   3. subscribe/publish → bridge typé ↔ brut
//   4. disconnect() → flush offline queue + cleanup
//
// Sous-systèmes référencés (créés dans les étapes suivantes) :
//   - SubscriptionRegistry      → étape 8
//   - MessageDeduplicator       → étape 7
//   - RealtimeTokenRefresher    → étape 6
//   - OfflineMessageQueue       → étape 9
//   - PayloadDecoder            → étape 10
//   - PayloadCompressor         → étape 11
//   - NetworkTransitionHandler  → étape 12
//   - ReconnectionManager       → étape 5

import Foundation
import WaanguCoreKit
import os

/// Unified-logging channel for the realtime client.
///
/// Deliberately not `print`: on a physical device with Xcode attached, `print`
/// writes to stdout over the debug connection, and a burst of them blocks the
/// calling thread long enough to register as a main-thread hang. `Logger`
/// writes to the unified logging system, which has no such back-pressure.
private let realtimeLog = Logger(subsystem: "com.waangu.realtimekit", category: "client")

/// Raw payload bodies for the inbound path.
///
/// Metadata (topic, size, outcome) is logged in every build; the body is not.
/// A chat frame carries message text, phone numbers and financial references,
/// and the unified log is readable off-device by anyone who can pair the phone
/// — so the body is compiled out of release builds entirely rather than merely
/// filtered at runtime.
enum RealtimeInboundLog {

    /// Max characters of a body to log. A media frame can run to megabytes and
    /// would push everything around it out of the log buffer.
    private static let maxBodyLength = 2_000

    static func body(topic: String, payload: Data) {
        #if DEBUG
        guard let text = String(data: payload, encoding: .utf8) else {
            realtimeLog.debug(
                "    body topic=\(topic, privacy: .public) <\(payload.count, privacy: .public) bytes, not UTF-8>"
            )
            return
        }
        let clipped = text.count > maxBodyLength
            ? String(text.prefix(maxBodyLength)) + "… (+\(text.count - maxBodyLength) chars)"
            : text
        realtimeLog.debug("    body topic=\(topic, privacy: .public) \(clipped, privacy: .public)")
        #endif
    }
}

// MARK: - RealtimeClient

/// Adapter central du système temps réel.
///
/// Les features ne voient jamais cette classe — elles reçoivent
/// `any RealtimeClientProtocol` via injection.
///
/// ```swift
/// // DependencyContainer
/// lazy var realtimeClient: any RealtimeClientProtocol = {
///     RealtimeAssembly.make(config: ...)
/// }()
/// ```
actor RealtimeClient: RealtimeClientProtocol {

    // MARK: - Core Dependencies

    /// Transport actif (MQTT, WebSocket, InMemory).
    private var transport: any RealtimeTransport

    /// Machine à états de la connexion.
    private let stateMachine: ConnectionStateMachine

    /// Configuration résolue du client.
    private let config: RealtimeClientConfig

    // MARK: - Sub-Systems

    /// Registry de toutes les souscriptions actives.
    private let subscriptionRegistry: SubscriptionRegistry

    /// Déduplication des messages entrants (QoS 1 re-delivery).
    private let deduplicator: MessageDeduplicator

    /// File d'attente hors ligne (persistée via StorageKit).
    public nonisolated let offlineQueue: any OfflineQueueProtocol

    /// Décodeur/encodeur JSON centralisé.
    private let payloadDecoder: PayloadDecoder

    /// Compresseur de payloads (gzip/identity).
    private let compressor: any PayloadCompressing

    // MARK: - Auth

    /// Delegate pour le refresh de token sur connexion vivante.
    private let authDelegate: any RealtimeAuthDelegate

    /// Refresher proactif du JWT.
    private let tokenRefresher: RealtimeTokenRefresher

    // MARK: - Reconnection

    /// Manager de reconnexion (exponential backoff + jitter).
    private let reconnectionManager: ReconnectionManager

    // MARK: - Metrics

    /// Delegate pour l'observabilité.
    private let metricsDelegate: (any RealtimeMetricsDelegate)?

    // MARK: - Topic Registrations

    /// Déclarations de topics enregistrées par les features au bootstrap.
    private var topicRegistrations: [TopicRegistration] = []

    // MARK: - Background Tasks

    /// Task de réception des messages du transport.
    private var receiveTask: Task<Void, Never>?

    /// Task d'observation des événements de connexion du transport.
    private var transportStateTask: Task<Void, Never>?

    /// Task de refresh proactif du token.
    private var tokenRefreshTask: Task<Void, Never>?

    // MARK: - Init

    /// Crée le RealtimeClient avec toutes ses dépendances.
    ///
    /// Appelé exclusivement par `RealtimeAssembly.make()`.
    /// Jamais instancié directement par les features ou le DependencyContainer.
    init(
        transport: any RealtimeTransport,
        config: RealtimeClientConfig,
        subscriptionRegistry: SubscriptionRegistry,
        deduplicator: MessageDeduplicator,
        offlineQueue: any OfflineQueueProtocol,
        payloadDecoder: PayloadDecoder,
        compressor: any PayloadCompressing,
        authDelegate: any RealtimeAuthDelegate,
        tokenRefresher: RealtimeTokenRefresher,
        reconnectionManager: ReconnectionManager,
        metricsDelegate: (any RealtimeMetricsDelegate)?
    ) {
        self.transport = transport
        self.stateMachine = ConnectionStateMachine(metricsDelegate: metricsDelegate)
        self.config = config
        self.subscriptionRegistry = subscriptionRegistry
        self.deduplicator = deduplicator
        self.offlineQueue = offlineQueue
        self.payloadDecoder = payloadDecoder
        self.compressor = compressor
        self.authDelegate = authDelegate
        self.tokenRefresher = tokenRefresher
        self.reconnectionManager = reconnectionManager
        self.metricsDelegate = metricsDelegate
    }

    deinit {
        receiveTask?.cancel()
        transportStateTask?.cancel()
        tokenRefreshTask?.cancel()
    }

    // =========================================================================
    // MARK: - Connection Lifecycle
    // =========================================================================

    var connectionState: RealtimeConnectionState {
        stateMachine.currentState
    }

    nonisolated func observeConnectionState() -> AsyncStream<RealtimeConnectionState> {
        // Chaque appelant reçoit son propre stream qui re-broadcaste la state machine.
        AsyncStream { continuation in
            let task = Task { [stateMachine] in
                for await state in stateMachine.stateStream {
                    continuation.yield(state)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func connect() async throws {
        // Already live — nothing to do.
        guard !stateMachine.isConnected else { return }

        // Avoid overlapping connect/auth; allow `.reconnecting` (startReconnection sets it).
        switch stateMachine.currentState {
        case .connecting, .authenticating:
            return
        default:
            break
        }

        // 1. Transition → connecting (valid from disconnected / reconnecting / suspended)
        guard stateMachine.transition(to: .connecting) else {
            return
        }

        do {
            // 2. Obtenir les credentials frais
            stateMachine.transition(to: .authenticating)
            let credentials = try await authDelegate.realtimeClientNeedsToken()

            // 3. Construire la config transport avec les credentials
            let transportConfig = config.buildTransportConfig(credentials: credentials)

            // 4. Valider la config
            let validationErrors = transportConfig.validate()
            guard validationErrors.isEmpty else {
                stateMachine.forceDisconnect(reason: .invalidConfiguration)
                throw RealtimeError.invalidConfiguration(
                    detail: validationErrors.joined(separator: "; ")
                )
            }

            // 5. Connecter le transport
            try await transport.connect(config: transportConfig)

            // 6. Transition → connected
            stateMachine.transition(to: .connected)

            // 7. Démarrer les boucles de fond
            startReceiveLoop()
            startTransportStateObservation()
            startTokenRefreshMonitoring(credentials: credentials)

            // 8. Re-souscrire les topics actifs (après reconnexion)
            try await resubscribeActiveTopics()

            // 9. Flush la offline queue
            await flushOfflineQueueIfNeeded()

            // 10. Reset le compteur de reconnexion
            await reconnectionManager.reset()

        } catch {
            stateMachine.forceDisconnect(reason: .serverClosed(code: nil))
            throw mapToRealtimeError(error)
        }
    }

    func disconnect(reason: DisconnectReason, flushQueue: Bool) async throws {
        // 1. Annuler les tasks de fond
        cancelBackgroundTasks()

        // 2. Flush la offline queue si demandé
        if flushQueue, stateMachine.isConnected {
            await flushOfflineQueueIfNeeded()
        }

        // 3. Annuler toutes les souscriptions
        await subscriptionRegistry.cancelAll()

        // 4. Déconnecter le transport
        do {
            try await transport.disconnect(reason: reason)
        } catch {
            // Log mais ne pas throw — la déconnexion doit réussir côté client.
            #if DEBUG
            realtimeLog.error("Transport disconnect error (ignored): \(error.localizedDescription, privacy: .public)")
            #endif
        }

        // 5. Transition → disconnected
        stateMachine.forceDisconnect(reason: reason)
    }

    // =========================================================================
    // MARK: - Subscribe
    // =========================================================================

    func subscribe<T: Decodable & Sendable>(
        to topic: RealtimeTopic,
        as type: T.Type,
        buffering: RealtimeBufferingPolicy,
        qos: RealtimeQoS
    ) async throws -> (stream: AsyncStream<T>, token: any RealtimeSubscriptionToken) {

        // 1. Vérifier l'état
        guard stateMachine.isConnected else {
            throw RealtimeError.notConnected
        }

        // 2. Vérifier la limite de souscriptions
        let currentCount = await subscriptionRegistry.activeCount
        if currentCount >= config.maxSubscriptions {
            throw RealtimeError.subscriptionLimitReached(
                current: currentCount,
                max: config.maxSubscriptions
            )
        }

        // 3. Créer le stream typé avec la buffering policy
        let (stream, continuation) = makeTypedStream(
            type: type,
            buffering: buffering
        )

        // 4. Enregistrer la souscription dans le registry
        let token = await subscriptionRegistry.register(
            topic: topic,
            qos: qos,
            buffering: buffering,
            continuation: AnyContinuation(continuation),
            decoder: { [payloadDecoder] data in
                try payloadDecoder.decode(type, from: data)
            }
        )

        // 5. Souscrire sur le transport
        do {
            try await transport.subscribe(topic: topic.path, qos: qos)
        } catch {
            // Rollback : annuler la souscription locale si le transport refuse.
            await subscriptionRegistry.remove(id: token.id)
            throw RealtimeError.subscriptionDenied(
                topic: topic.path,
                reason: error.localizedDescription
            )
        }

        // 6. Métriques
        Task { [metricsDelegate] in
            await metricsDelegate?.didChangeSubscriptionCount(
                activeCount: currentCount + 1,
                event: .added(topic: topic)
            )
        }

        return (stream, token)
    }

    // =========================================================================
    // MARK: - Publish
    // =========================================================================

    func publish<T: Encodable & Sendable>(
        _ payload: T,
        to topic: RealtimeTopic,
        qos: RealtimeQoS,
        priority: MessagePriority
    ) async throws {

        // 1. Encoder le payload
        let data: Data
        do {
            data = try payloadDecoder.encode(payload)
        } catch {
            throw RealtimeError.encodingFailed(
                type: String(describing: T.self),
                underlyingDescription: error.localizedDescription
            )
        }

        // 2. Vérifier la taille
        guard data.count <= config.maxPayloadSize else {
            throw RealtimeError.payloadTooLarge(
                size: data.count,
                maxAllowed: config.maxPayloadSize
            )
        }

        // 3. Compresser si activé
        let finalData = config.compressionEnabled
            ? (try? compressor.compress(data)) ?? data
            : data

        // 4. Générer le message ID
        let messageId = MessageID()

        // 5. Envoyer ou mettre en file selon l'état
        if stateMachine.isConnected {
            try await publishToTransport(
                data: finalData, topic: topic, qos: qos, messageId: messageId
            )
        } else if stateMachine.canAcceptOutgoing {
            // En reconnexion → offline queue (données non compressées pour re-compression au flush).
            try await enqueueOffline(
                data: data, topic: topic, qos: qos,
                priority: priority, messageId: messageId
            )
        } else {
            throw RealtimeError.notConnected
        }
    }

    // =========================================================================
    // MARK: - Request-Reply
    // =========================================================================

    func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ payload: Request,
        to topic: RealtimeTopic,
        replyOn replyTopic: RealtimeTopic,
        as responseType: Response.Type,
        timeout: TimeInterval
    ) async throws -> Response {

        // 1. Générer le correlation ID
        let correlationId = MessageID()

        // 2. Souscrire au topic de réponse AVANT de publier la requête
        let (replyStream, replyToken) = try await subscribe(
            to: replyTopic,
            as: Response.self,
            buffering: .bufferNewest(1),
            qos: .atLeastOnce
        )

        defer {
            Task { [replyToken] in await replyToken.cancel() }
        }

        // 3. Encoder le payload avec le correlationId
        let requestWrapper = CorrelatedPayload(
            correlationId: correlationId,
            payload: payload
        )

        // 4. Publier la requête
        try await publish(requestWrapper, to: topic, qos: .atLeastOnce, priority: .high)

        // 5. Attendre la réponse avec timeout
        return try await withRealtimeTimeout(timeout, correlationId: correlationId) {
            for await response in replyStream {
                return response
            }
            throw RealtimeError.requestTimeout(
                correlationId: correlationId.uuidString,
                timeout: timeout
            )
        }
    }

    // =========================================================================
    // MARK: - Presence
    // =========================================================================

    func publishPresence(
        _ state: PresenceState,
        to topic: RealtimeTopic
    ) async throws {
        let info = PresenceInfo(
            userId: config.userId ?? "unknown",
            state: state,
            lastSeen: Date(),
            deviceId: config.deviceInfo.deviceId
        )
        try await publish(info, to: topic, qos: .fireAndForget, priority: .low)
    }

    nonisolated func observePresence(
        on topic: RealtimeTopic
    ) -> AsyncStream<PresenceInfo> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let (stream, _) = try await self.subscribe(
                        to: topic,
                        as: PresenceInfo.self,
                        buffering: .debounce(interval: 0.5),
                        qos: .fireAndForget
                    )
                    for await presence in stream {
                        continuation.yield(presence)
                    }
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // =========================================================================
    // MARK: - Subscription Management
    // =========================================================================

    func cancelSubscription(_ token: any RealtimeSubscriptionToken) async {
        let topic = token.topic
        await token.cancel()
        await subscriptionRegistry.remove(id: token.id)

        // Se désabonner du transport si plus aucune souscription sur ce topic.
        let remainingOnTopic = await subscriptionRegistry.count(for: topic)
        if remainingOnTopic == 0 {
            try? await transport.unsubscribe(topic: topic.path)
        }

        let activeCount = await subscriptionRegistry.activeCount
        Task { [metricsDelegate] in
            await metricsDelegate?.didChangeSubscriptionCount(
                activeCount: activeCount,
                event: .removed(topic: topic)
            )
        }
    }

    func cancelAllSubscriptions(forFeature feature: String) async {
        let tokens = await subscriptionRegistry.tokens(forFeature: feature)
        for token in tokens {
            await cancelSubscription(token)
        }

        let activeCount = await subscriptionRegistry.activeCount
        Task { [metricsDelegate] in
            await metricsDelegate?.didChangeSubscriptionCount(
                activeCount: activeCount,
                event: .cancelledAll(feature: feature)
            )
        }
    }

    var activeSubscriptionCount: Int {
        get async { await subscriptionRegistry.activeCount }
    }

    func isSubscribed(to topic: RealtimeTopic) async -> Bool {
        await subscriptionRegistry.hasSubscription(for: topic)
    }

    func subscriptionDiagnostics() async -> [RealtimeSubscriptionDiagnostic] {
        await subscriptionRegistry.diagnostics()
    }

    // MARK: - Topic Registration

    func register(_ registrations: [TopicRegistration]) async {
        topicRegistrations.append(contentsOf: registrations)
    }

    // =========================================================================
    // MARK: - Private — Receive Loop
    // =========================================================================

    /// Démarre la boucle de réception des messages du transport.
    ///
    /// Consomme le stream brut, déduplique, décode, et dispatch
    /// vers les souscriptions typées.
    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.transport.incomingMessages()
            for await rawMessage in stream {
                guard !Task.isCancelled else { break }
                await self.handleIncomingMessage(rawMessage)
            }
        }
    }

    /// Traite un message brut reçu du transport.
    private func handleIncomingMessage(_ raw: RawTransportMessage) async {
        // 1. Déduplication (si le broker fournit un ID)
        if let brokerId = raw.brokerMessageId {
            let messageId = UUID(uuidString: brokerId) ?? UUID()
            let isDuplicate = await deduplicator.isDuplicate(messageId)
            if isDuplicate {
                realtimeLog.debug(
                    "\u{1F501} IN  drop=duplicate topic=\(raw.topic, privacy: .public) brokerId=\(brokerId, privacy: .public)"
                )
                Task { [metricsDelegate] in
                    await metricsDelegate?.didDeduplicateMessage(
                        topic: RealtimeTopic(raw.topic),
                        messageId: messageId
                    )
                }
                return
            }
            await deduplicator.markSeen(messageId)
        }

        // 2. Décompresser si nécessaire
        let payload: Data
        if config.compressionEnabled {
            payload = (try? compressor.decompress(raw.payload)) ?? raw.payload
        } else {
            payload = raw.payload
        }

        // 3. Trouver les souscriptions qui matchent ce topic
        let match = await subscriptionRegistry.subscriptions(matching: raw.topic, payload: payload)

        // Ne rien conclure d'une liste de dispatch vide : une souscription en
        // debounce a bien matché, elle émettra plus tard. Seul `matchedCount`
        // distingue « personne n'écoute » de « personne n'écoute maintenant ».
        guard !match.isUnsubscribed else {
            realtimeLog.warning(
                "\u{1F4E5} IN  drop=no-subscriber topic=\(raw.topic, privacy: .public) bytes=\(payload.count, privacy: .public)"
            )
            RealtimeInboundLog.body(topic: raw.topic, payload: payload)
            return
        }

        // One line per inbound frame, before any decode can drop it. `deferred`
        // is the count a temporal buffering policy is holding back — the number
        // that tells a silent debounce apart from a topic nobody listens to.
        realtimeLog.info(
            """
            \u{1F4E5} IN  topic=\(raw.topic, privacy: .public) \
            bytes=\(payload.count, privacy: .public) \
            dispatch=\(match.dispatches.count, privacy: .public) \
            deferred=\(match.deferredCount, privacy: .public)
            """
        )
        RealtimeInboundLog.body(topic: raw.topic, payload: payload)

        // 4. Décoder et dispatcher vers chaque souscription immédiate.
        for subscription in match.dispatches {
            do {
                let decoded = try subscription.decode(payload)
                subscription.yield(decoded)
            } catch {
                // The one drop that used to leave no trace at all: the frame
                // arrived, matched a subscription, and failed to become the
                // type that subscription asked for. Only metrics saw it.
                realtimeLog.error(
                    """
                    \u{26A0}\u{FE0F} IN  drop=decode-failed topic=\(raw.topic, privacy: .public) \
                    bytes=\(payload.count, privacy: .public) \
                    error=\(String(describing: error), privacy: .public)
                    """
                )
                Task { [metricsDelegate] in
                    await metricsDelegate?.didLoseMessage(
                        topic: RealtimeTopic(raw.topic),
                        reason: .decodingFailure(topic: raw.topic)
                    )
                }
            }
        }

        // 5. Métriques — latence si le serveur a envoyé un timestamp
        let latency: TimeInterval? = raw.properties["serverTimestamp"]
            .flatMap { Double($0) }
            .map { raw.receivedAt.timeIntervalSince(Date(timeIntervalSince1970: $0)) }

        Task { [metricsDelegate] in
            await metricsDelegate?.didReceiveMessage(
                topic: RealtimeTopic(raw.topic),
                latency: latency,
                size: payload.count
            )
        }
    }

    // =========================================================================
    // MARK: - Private — Transport State Observation
    // =========================================================================

    /// Observe les événements de connexion du transport
    /// et déclenche la reconnexion automatique si nécessaire.
    private func startTransportStateObservation() {
        transportStateTask?.cancel()
        transportStateTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.transport.connectionStateStream()
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self.handleTransportEvent(event)
            }
        }
    }

    /// Réagit à un événement de connexion du transport.
    private func handleTransportEvent(_ event: TransportConnectionEvent) async {
        switch event {

        case .connected:
            if !stateMachine.isConnected {
                stateMachine.transition(to: .connected)
            }

        case .disconnected(_, let isRecoverable) where isRecoverable:
            await startReconnection()

        case .disconnected(let error, _):
            stateMachine.forceDisconnect(
                reason: .protocolError(description: error ?? "Unknown")
            )

        case .heartbeatTimeout:
            await startReconnection()

        case .authenticationRejected(let reason):
            // Attempt token refresh + soft reconnect before giving up.
            do {
                _ = try await authDelegate.realtimeClientNeedsToken()
                try await reconnectPreservingSubscriptions(reason: .tokenExpired)
            } catch {
                stateMachine.forceDisconnect(reason: .tokenExpired)
                await authDelegate.realtimeClientDidFailAuthentication(
                    error: .authenticationFailed(reason: reason)
                )
            }

        case .serverDisconnect(let code, _):
            // Keep registry; reconnect will resubscribe active topics.
            await startReconnection()

        case .connecting, .handshaking:
            break
        }
    }

    // =========================================================================
    // MARK: - Private — Reconnection
    // =========================================================================

    /// Démarre le cycle de reconnexion automatique.
    private func startReconnection() async {
        guard !Task.isCancelled else { return }

        let attempt = (stateMachine.reconnectionAttempt ?? 0) + 1
        let delay = await reconnectionManager.nextDelay(attempt: attempt)

        guard let delay else {
            // Max attempts atteint → abandon.
            stateMachine.forceDisconnect(reason: .allTransportsFailed)
            return
        }

        stateMachine.transition(to: .reconnecting(attempt: attempt, nextRetryIn: delay))

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }

        do {
            try await connect()
        } catch {
            // connect() échoue → handleTransportEvent relancera startReconnection
            // quand le transport émet .disconnected.
        }
    }

    // =========================================================================
    // MARK: - Private — Token Refresh Monitoring
    // =========================================================================

    /// Surveille l'expiration du token et déclenche le refresh proactif.
    private func startTokenRefreshMonitoring(credentials: RealtimeCredentials) {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.tokenRefresher.startMonitoring(
                credentials: credentials,
                delegate: self.authDelegate,
                onNewCredentials: { [weak self] newCredentials in
                    guard let self else { return }
                    let success = try await self.transport.reauthenticate(
                        with: newCredentials
                    )
                    if !success {
                        // Soft reconnect: keep subscription registry so topics resubscribe.
                        try await self.reconnectPreservingSubscriptions(reason: .tokenExpired)
                    }
                }
            )
        }
    }

    // =========================================================================
    // MARK: - Private — Helpers
    // =========================================================================

    /// Drop the transport and reconnect without `cancelAll()` on the registry,
    /// so `resubscribeActiveTopics()` can restore MQTT subscriptions.
    private func reconnectPreservingSubscriptions(reason: DisconnectReason) async throws {
        cancelBackgroundTasks()
        do {
            try await transport.disconnect(reason: reason)
        } catch {
            #if DEBUG
            realtimeLog.error("Soft reconnect transport disconnect error (ignored): \(error.localizedDescription, privacy: .public)")
            #endif
        }
        stateMachine.forceDisconnect(reason: reason)
        try await connect()
    }

    /// Re-souscrit à tous les topics actifs (après reconnexion).
    private func resubscribeActiveTopics() async throws {
        let activeTopics = await subscriptionRegistry.activeTopicsWithQoS()
        for (topicPath, qos) in activeTopics {
            try await transport.subscribe(topic: topicPath, qos: qos)
        }
    }

    /// Flush la offline queue en envoyant les messages pendants.
    private func flushOfflineQueueIfNeeded() async {
        let startTime = Date()
        let result = await offlineQueue.flush { [weak self] item in
            guard let self, await self.stateMachine.isConnected else {
                return false
            }
            do {
                try await self.publishToTransport(
                    data: item.payloadData,
                    topic: item.topic,
                    qos: item.qos,
                    messageId: item.id
                )
                return true
            } catch {
                return false
            }
        }

        if result.totalProcessed > 0 {
            Task { [metricsDelegate] in
                await metricsDelegate?.didFlushOfflineQueue(
                    messageCount: result.sentCount,
                    expiredCount: result.expiredCount,
                    duration: Date().timeIntervalSince(startTime)
                )
            }
        }
    }

    /// Publie directement sur le transport.
    private func publishToTransport(
        data: Data,
        topic: RealtimeTopic,
        qos: RealtimeQoS,
        messageId: MessageID
    ) async throws {
        let startTime = Date()
        do {
            try await transport.publish(
                data: data, to: topic.path, qos: qos, messageId: messageId
            )
            let latency = Date().timeIntervalSince(startTime)
            Task { [metricsDelegate] in
                await metricsDelegate?.didPublishMessage(
                    topic: topic, qos: qos, latency: latency
                )
            }
        } catch {
            throw RealtimeError.publishFailed(
                topic: topic.path,
                reason: error.localizedDescription
            )
        }
    }

    /// Enqueue un message dans la offline queue.
    private func enqueueOffline(
        data: Data,
        topic: RealtimeTopic,
        qos: RealtimeQoS,
        priority: MessagePriority,
        messageId: MessageID
    ) async throws {
        let item = OfflineQueueItem(
            id: messageId,
            topic: topic,
            payloadData: data,
            qos: qos,
            priority: priority,
            timestamp: Date(),
            ttl: config.defaultMessageTTL
        )
        try await offlineQueue.enqueue(item)
    }

    /// Crée un AsyncStream typé avec la buffering policy appropriée.
    private func makeTypedStream<T: Decodable & Sendable>(
        type: T.Type,
        buffering: RealtimeBufferingPolicy
    ) -> (AsyncStream<T>, AsyncStream<T>.Continuation) {
        // Note : AsyncStream.makeStream est disponible depuis Swift 5.9.
        // La bufferingPolicy native gère unbounded, bufferNewest, bufferOldest.
        // Throttle et debounce sont gérés par le SubscriptionRegistry (temporal processing).
        switch buffering {
        case .unbounded:
            return AsyncStream<T>.makeStream(bufferingPolicy: .unbounded)
        case .bufferNewest(let n):
            return AsyncStream<T>.makeStream(bufferingPolicy: .bufferingNewest(n))
        case .bufferOldest(let n):
            return AsyncStream<T>.makeStream(bufferingPolicy: .bufferingOldest(n))
        case .throttle, .debounce:
            // Pour throttle/debounce, on utilise bufferNewest(1) comme base.
            // Le filtrage temporel est appliqué dans le dispatch (SubscriptionRegistry).
            return AsyncStream<T>.makeStream(bufferingPolicy: .bufferingNewest(1))
        }
    }

    /// Mappe une erreur arbitraire vers un RealtimeError.
    private func mapToRealtimeError(_ error: Error) -> RealtimeError {
        if let realtimeError = error as? RealtimeError {
            return realtimeError
        }
        return .transportError(
            transportName: transport.transportName,
            description: error.localizedDescription
        )
    }

    /// Annule toutes les tasks de fond.
    private func cancelBackgroundTasks() {
        receiveTask?.cancel()
        transportStateTask?.cancel()
        tokenRefreshTask?.cancel()
        receiveTask = nil
        transportStateTask = nil
        tokenRefreshTask = nil
    }
}

// MARK: - CorrelatedPayload (Request-Reply)

/// Wrapper interne qui ajoute le correlationId au payload pour le request-reply.
struct CorrelatedPayload<T: Encodable & Sendable>: Encodable, Sendable {
    let correlationId: MessageID
    let payload: T
}

// MARK: - Timeout Helper

/// Exécute une opération async avec un timeout.
///
/// Utilise un TaskGroup : la première task qui finit (opération ou timer) gagne.
/// Si le timer gagne, l'opération est annulée et une erreur est lancée.
func withRealtimeTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    correlationId: MessageID,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw RealtimeError.requestTimeout(
                correlationId: correlationId.uuidString,
                timeout: timeout
            )
        }
        guard let result = try await group.next() else {
            throw RealtimeError.requestTimeout(
                correlationId: correlationId.uuidString,
                timeout: timeout
            )
        }
        group.cancelAll()
        return result
    }
}

// MARK: - AnyContinuation (Type Erasure)

/// Type-erased wrapper pour les continuations de souscription.
///
/// Le SubscriptionRegistry stocke des souscriptions de types différents
/// (`AsyncStream<ChatMessage>.Continuation`, `AsyncStream<DriverPosition>.Continuation`)
/// dans une collection homogène grâce à ce type erasure.
struct AnyContinuation: Sendable {
    private let _yield: @Sendable (Any) -> Void
    private let _finish: @Sendable () -> Void

    init<T: Sendable>(_ continuation: AsyncStream<T>.Continuation) {
        self._yield = { value in
            if let typed = value as? T {
                continuation.yield(typed)
            }
        }
        self._finish = {
            continuation.finish()
        }
    }

    /// Émet une valeur vers le stream sous-jacent.
    func yield(_ value: Any) { _yield(value) }

    /// Termine le stream sous-jacent.
    func finish() { _finish() }
}

// MARK: - RealtimeClientConfig

/// Configuration interne résolue du RealtimeClient.
///
/// Construite par `RealtimeAssembly` à partir de la config publique.
/// Porte les paramètres de comportement du client (pas du transport).
struct RealtimeClientConfig: Sendable {

    /// Identifiant de l'utilisateur courant (extrait du JWT).
    let userId: String?

    /// Informations sur le device.
    let deviceInfo: RealtimeDeviceInfo

    /// Nombre maximum de souscriptions simultanées.
    let maxSubscriptions: Int

    /// Taille maximale d'un payload (bytes).
    let maxPayloadSize: Int

    /// TTL par défaut pour les messages dans la offline queue. `nil` = infini.
    let defaultMessageTTL: TimeInterval?

    /// `true` si la compression est activée.
    let compressionEnabled: Bool

    // MARK: - Transport Config Builder

    /// Host du broker.
    let host: String

    /// Port du broker.
    let port: UInt16

    /// Configuration TLS.
    let tlsConfig: TransportTLSConfig

    /// Identifiant unique du client auprès du broker.
    let clientId: String

    /// Intervalle de heartbeat.
    let heartbeatInterval: TimeInterval

    /// Timeout de heartbeat.
    let heartbeatTimeout: TimeInterval

    /// Options spécifiques au protocole.
    let protocolOptions: TransportProtocolOptions

    /// Construit une `RealtimeTransportConfig` complète avec des credentials frais.
    ///
    /// Appelé à chaque connexion/reconnexion car les credentials changent.
    func buildTransportConfig(credentials: RealtimeCredentials) -> RealtimeTransportConfig {
        RealtimeTransportConfig(
            host: host,
            port: port,
            tlsConfig: tlsConfig,
            credentials: credentials,
            clientId: clientId,
            deviceInfo: deviceInfo,
            heartbeatInterval: heartbeatInterval,
            heartbeatTimeout: heartbeatTimeout,
            maxPayloadSize: maxPayloadSize,
            compressionEnabled: compressionEnabled,
            protocolOptions: protocolOptions
        )
    }
}
