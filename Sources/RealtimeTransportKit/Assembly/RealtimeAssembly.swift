// MARK: - RealtimeKit/Assembly/RealtimeAssembly.swift
//
// Module  : RealtimeKit (public — seul point d'entrée)
// Rôle    : Factory publique qui crée et câble tous les sous-systèmes
//           du RealtimeClient. Équivalent de DatabaseAssembly dans StorageKit.
//
// Design  : Le DependencyContainer appelle `RealtimeAssembly.make(config:)`
//           et reçoit un `any RealtimeClientProtocol`. C'est le SEUL type
//           que l'App Target importe depuis RealtimeKit.
//
//           RealtimeAssembly.make() :
//           1. Résout la configuration interne
//           2. Crée le transport selon le type choisi
//           3. Instancie tous les sous-systèmes
//           4. Câble le RealtimeClient avec ses dépendances
//           5. Retourne `any RealtimeClientProtocol`
//
// Pattern : Identique à DatabaseAssembly :
//           DatabaseAssembly.make(engine: .sqlite)  → any DatabaseRepositoryProtocol
//           RealtimeAssembly.make(config: ...)       → any RealtimeClientProtocol
//
// Visibilité :
//   PUBLIC  : RealtimeAssembly, RealtimeConfiguration, TransportType
//   INTERNE : tout le reste (RealtimeClient, transports, sous-systèmes)

import Foundation
import WaanguCoreKit

// MARK: - RealtimeAssembly

/// Point d'entrée unique de RealtimeKit vers l'App Target.
///
/// ```swift
/// // DependencyContainer.swift
/// lazy var realtimeClient: any RealtimeClientProtocol = {
///     RealtimeAssembly.make(config: .init(
///         transport: .mqtt,
///         host: appConfig.realtimeHost,
///         port: appConfig.realtimePort,
///         useTLS: true,
///         authDelegate: makeRealtimeAuthBridge(),
///         deviceInfo: deviceInfo,
///         networkMonitor: networkMonitor,
///         deviceTier: deviceTier,
///         performanceMonitor: performanceMonitor,
///         metricsDelegate: RealtimeMetricsCollector.shared
///     ))
/// }()
/// ```
public enum RealtimeAssembly {

    // MARK: - Factory

    /// Crée un `RealtimeClientProtocol` entièrement configuré.
    ///
    /// C'est la seule méthode que l'App Target appelle.
    /// Tout le câblage interne est masqué.
    ///
    /// - Parameter config: Configuration publique fournie par le DependencyContainer.
    /// - Returns: Un client temps réel prêt à l'emploi.
    public static func make(
        config: RealtimeConfiguration
    ) -> any RealtimeClientProtocol {

        // 1. Résoudre la configuration interne du client
        let clientConfig = resolveClientConfig(from: config)

        // 2. Créer le transport selon le type choisi
        let transport = createTransport(
            type: config.transport,
            fallback: config.fallback
        )

        // 3. Créer les sous-systèmes
        let subscriptionRegistry = SubscriptionRegistry()

        let deduplicator = MessageDeduplicator(
            windowSize: config.deduplicationWindowSize,
            ttl: config.deduplicationTTL
        )

        let offlineQueue = createOfflineQueue(config: config.offlineQueueConfig)

        let payloadDecoder = PayloadDecoder(
            dateDecodingStrategy: config.dateDecodingStrategy,
            keyDecodingStrategy: config.keyDecodingStrategy
        )

        let compressor = createCompressor(enabled: config.compressionEnabled)

        let tokenRefresher = RealtimeTokenRefresher(
            threshold: config.authDelegate.tokenRefreshThreshold
        )

        let reconnectionManager = ReconnectionManager(
            policy: config.reconnectionPolicy
        )

        // 4. Câbler le RealtimeClient
        let client = RealtimeClient(
            transport: transport,
            config: clientConfig,
            subscriptionRegistry: subscriptionRegistry,
            deduplicator: deduplicator,
            offlineQueue: offlineQueue,
            payloadDecoder: payloadDecoder,
            compressor: compressor,
            authDelegate: config.authDelegate,
            tokenRefresher: tokenRefresher,
            reconnectionManager: reconnectionManager,
            metricsDelegate: config.metricsDelegate
        )

        return client
    }

    // MARK: - For Testing

    /// Crée un client temps réel avec le transport InMemory.
    ///
    /// Raccourci pour les tests unitaires et les previews SwiftUI.
    /// Pas de réseau, pas de broker — tout est en mémoire.
    ///
    /// ```swift
    /// // Tests
    /// let (client, transport) = RealtimeAssembly.makeInMemory()
    /// // Simuler un message entrant :
    /// await transport.simulateIncoming(topic: "chat/1/messages", payload: data)
    /// ```
    ///
    /// - Parameter authDelegate: Delegate d'auth (optionnel, un stub est utilisé par défaut).
    /// - Returns: Le client + le transport InMemory pour les simulations.
    public static func makeInMemory(
        authDelegate: (any RealtimeAuthDelegate)? = nil
    ) -> (client: any RealtimeClientProtocol, transport: InMemoryTransport) {

        let inMemoryTransport = InMemoryTransport()
        let resolvedAuthDelegate = authDelegate ?? StubAuthDelegate()

        let clientConfig = RealtimeClientConfig(
            userId: "test-user",
            deviceInfo: RealtimeDeviceInfo(
                deviceId: "test-device",
                platform: "test",
                appVersion: "0.0.0"
            ),
            maxSubscriptions: 100,
            maxPayloadSize: 1_048_576,
            defaultMessageTTL: nil,
            compressionEnabled: false,
            host: "localhost",
            port: 0,
            tlsConfig: .disabled,
            clientId: "test-client",
            heartbeatInterval: 60,
            heartbeatTimeout: 90,
            protocolOptions: TransportProtocolOptions()
        )

        let client = RealtimeClient(
            transport: inMemoryTransport,
            config: clientConfig,
            subscriptionRegistry: SubscriptionRegistry(),
            deduplicator: MessageDeduplicator(windowSize: 100, ttl: 60),
            offlineQueue: InMemoryOfflineQueue(),
            payloadDecoder: PayloadDecoder(),
            compressor: IdentityCompressor(),
            authDelegate: resolvedAuthDelegate,
            tokenRefresher: RealtimeTokenRefresher(threshold: 60),
            reconnectionManager: ReconnectionManager(policy: .standard),
            metricsDelegate: nil
        )

        return (client, inMemoryTransport)
    }

    // MARK: - Internal — Configuration Resolution

    /// Résout la configuration interne à partir de la config publique.
    private static func resolveClientConfig(
        from config: RealtimeConfiguration
    ) -> RealtimeClientConfig {

        // Construire le clientId déterministe à partir du deviceId.
        let clientId = config.clientId
            ?? "waangu-\(config.deviceInfo.platform.lowercased())-\(config.deviceInfo.deviceId)"

        return RealtimeClientConfig(
            userId: config.userId,
            deviceInfo: config.deviceInfo,
            maxSubscriptions: config.maxSubscriptions,
            maxPayloadSize: config.maxPayloadSize,
            defaultMessageTTL: config.defaultMessageTTL,
            compressionEnabled: config.compressionEnabled,
            host: config.host,
            port: config.port,
            tlsConfig: resolveTLSConfig(from: config),
            clientId: clientId,
            heartbeatInterval: config.heartbeatInterval,
            heartbeatTimeout: config.heartbeatInterval * 1.5,
            protocolOptions: resolveProtocolOptions(from: config)
        )
    }

    /// Résout la configuration TLS.
    private static func resolveTLSConfig(
        from config: RealtimeConfiguration
    ) -> TransportTLSConfig {
        if !config.useTLS {
            return .disabled
        }
        if let keyHashes = config.pinnedPublicKeyHashes, !keyHashes.isEmpty {
            return .pinned(publicKeyHashes: keyHashes)
        }
        return .standard
    }

    /// Résout les options spécifiques au protocole.
    private static func resolveProtocolOptions(
        from config: RealtimeConfiguration
    ) -> TransportProtocolOptions {
        TransportProtocolOptions(
            mqttVersion: config.mqttVersion ?? .v5_0,
            mqttCleanSession: config.mqttCleanSession ?? true,
            mqttLastWill: config.lastWillConfig,
            mqttRetainSupported: config.mqttRetainSupported ?? false,
            mqttReceiveMaximum: config.mqttReceiveMaximum ?? 65535,
            mqttSessionExpiryInterval: config.mqttSessionExpiryInterval ?? 3600,
            mqttTopicAliasMaximum: config.mqttTopicAliasMaximum ?? 0,
            webSocketPath: config.webSocketPath ?? "/ws",
            webSocketSubprotocols: config.webSocketSubprotocols ?? [],
            webSocketHeaders: config.webSocketHeaders ?? [:]
        )
    }

    // MARK: - Internal — Transport Creation

    /// Crée le transport principal selon le type choisi.
    private static func createTransport(
        type: TransportType,
        fallback: TransportFallbackConfig?
    ) -> any RealtimeTransport {
        // Si un fallback chain est configuré, wraper dans un TransportFallbackChain.
        if let fallback, fallback.chain.count > 1 {
            return TransportFallbackChain(
                config: fallback,
                factory: createSingleTransport
            )
        }
        return createSingleTransport(type)
    }

    /// Crée un transport unique selon son type.
    private static func createSingleTransport(_ type: TransportType) -> any RealtimeTransport {
        switch type {
        case .mqtt:
            return MQTTTransport()
        case .webSocket:
            // WebSocketTransport standalone à implémenter à l'étape 18.
            // Fallback sur InMemory pour l'instant (ne pas utiliser en production).
            assertionFailure("WebSocketTransport not yet implemented — use .mqtt")
            return InMemoryTransport()
        case .inMemory:
            return InMemoryTransport()
        }
    }

    // MARK: - Internal — Sub-system Creation

    /// Crée la offline queue selon la config.
    private static func createOfflineQueue(
        config: OfflineQueueConfiguration
    ) -> any OfflineQueueProtocol {
        if config.persistent {
            // TODO: Étape 9 — OfflineMessageQueue avec StorageKit.
            // Pour l'instant, fallback sur InMemory.
            return InMemoryOfflineQueue(config: config)
        }
        return InMemoryOfflineQueue(config: config)
    }

    /// Crée le compresseur selon la config.
    private static func createCompressor(enabled: Bool) -> any PayloadCompressing {
        if enabled {
            return GzipCompressor()
        }
        return IdentityCompressor()
    }
}

// MARK: - RealtimeConfiguration (Public)

/// Configuration publique fournie par le DependencyContainer.
///
/// C'est le seul type de configuration que l'App Target manipule.
/// Les détails internes (transport config, protocol options) sont
/// résolus par `RealtimeAssembly`.
///
/// ```swift
/// RealtimeConfiguration(
///     transport: .mqtt,
///     host: "mqtt.waangu.com",
///     port: 8883,
///     useTLS: true,
///     authDelegate: realtimeAuthBridge,
///     deviceInfo: deviceInfo,
///     networkMonitor: networkMonitor,
///     deviceTier: deviceTier,
///     performanceMonitor: performanceMonitor
/// )
/// ```
public struct RealtimeConfiguration: Sendable {

    // MARK: - Transport

    /// Type de transport principal.
    public let transport: TransportType

    /// Configuration de fallback (optionnelle).
    /// Si configuré, les transports sont essayés dans l'ordre.
    public let fallback: TransportFallbackConfig?

    // MARK: - Connection

    /// Hostname du broker/serveur.
    public let host: String

    /// Port de connexion.
    public let port: UInt16

    /// `true` pour activer TLS/SSL.
    public let useTLS: Bool

    /// Hashes de clés publiques pour le certificate pinning.
    /// `nil` = pas de pinning (validation TLS standard).
    public let pinnedPublicKeyHashes: [String]?

    // MARK: - Auth

    /// Delegate pour le refresh de token sur connexion vivante.
    public let authDelegate: any RealtimeAuthDelegate

    /// Identifiant de l'utilisateur courant (optionnel — peut être dans le JWT).
    public let userId: String?

    // MARK: - Device

    /// Informations sur le device (pour multi-device et métriques).
    public let deviceInfo: RealtimeDeviceInfo

    // MARK: - NetworkKit Dependencies (CONSOMMÉS, pas recrées)

    /// Moniteur réseau existant de NetworkKit.
    /// Utilisé pour la détection de transitions WiFi ↔ Cellular.
    public let networkMonitor: (any NetworkMonitoringProtocol)?

    /// Tier du device existant de NetworkKit.
    /// Utilisé pour adapter heartbeat, buffer sizes, reconnection.
    public let deviceTier: (any DeviceTierProtocol)?

    /// Moniteur de performance existant de NetworkKit.
    /// Utilisé pour réduire l'activité sous pression mémoire/CPU/thermique.
    public let performanceMonitor: (any PerformanceMonitorProtocol)?

    // MARK: - Reconnection

    /// Politique de reconnexion.
    public let reconnectionPolicy: ReconnectionPolicy

    // MARK: - Heartbeat

    /// Intervalle de heartbeat/keep-alive (secondes).
    public let heartbeatInterval: TimeInterval

    // MARK: - Limits

    /// Nombre maximum de souscriptions simultanées.
    public let maxSubscriptions: Int

    /// Taille maximale d'un payload (bytes).
    public let maxPayloadSize: Int

    /// TTL par défaut pour les messages dans la offline queue.
    public let defaultMessageTTL: TimeInterval?

    // MARK: - Compression

    /// `true` pour activer la compression des payloads.
    public let compressionEnabled: Bool

    // MARK: - Offline Queue

    /// Configuration de la file d'attente hors ligne.
    public let offlineQueueConfig: OfflineQueueConfiguration

    // MARK: - Deduplication

    /// Nombre d'IDs de messages retenus pour la déduplication.
    public let deduplicationWindowSize: Int

    /// Durée de rétention des IDs pour la déduplication (secondes).
    public let deduplicationTTL: TimeInterval

    // MARK: - Parsing

    /// Stratégie de décodage des dates JSON.
    public let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy

    /// Stratégie de décodage des clés JSON.
    public let keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy

    // MARK: - Metrics

    /// Delegate pour l'observabilité. `nil` = pas de métriques.
    public let metricsDelegate: (any RealtimeMetricsDelegate)?

    // MARK: - Protocol-Specific (optionnel — l'App Target peut ignorer)

    /// Client ID custom. `nil` = généré automatiquement depuis deviceId.
    public let clientId: String?

    /// Version MQTT. `nil` = v5.0 par défaut.
    public let mqttVersion: MQTTVersion?

    /// Clean session MQTT. `nil` = true par défaut.
    public let mqttCleanSession: Bool?

    /// Retain MQTT supporté. `nil` = false par défaut.
    public let mqttRetainSupported: Bool?

    /// Receive maximum MQTT. `nil` = 65535 par défaut.
    public let mqttReceiveMaximum: UInt16?

    /// Session expiry interval (secondes). MQTT 5.0 uniquement.
    /// Le broker garde les souscriptions pendant cette durée après déconnexion.
    /// `nil` = 3600 (1 heure) par défaut.
    public let mqttSessionExpiryInterval: UInt32?

    /// Topic alias maximum. MQTT 5.0 uniquement.
    /// `nil` = 10 par défaut.
    public let mqttTopicAliasMaximum: UInt16?

    /// Last Will and Testament config (optionnel).
    public let lastWillConfig: LastWillConfig?

    /// Path WebSocket. `nil` = "/ws" par défaut.
    public let webSocketPath: String?

    /// Sous-protocoles WebSocket. `nil` = [] par défaut.
    public let webSocketSubprotocols: [String]?

    /// Headers WebSocket additionnels. `nil` = [:] par défaut.
    public let webSocketHeaders: [String: String]?

    // MARK: - Init

    public init(
        // Required
        transport: TransportType,
        host: String,
        port: UInt16,
        useTLS: Bool = true,
        authDelegate: any RealtimeAuthDelegate,
        deviceInfo: RealtimeDeviceInfo,

        // NetworkKit dependencies
        networkMonitor: (any NetworkMonitoringProtocol)? = nil,
        deviceTier: (any DeviceTierProtocol)? = nil,
        performanceMonitor: (any PerformanceMonitorProtocol)? = nil,

        // Optionals with sensible defaults
        fallback: TransportFallbackConfig? = nil,
        pinnedPublicKeyHashes: [String]? = nil,
        userId: String? = nil,
        reconnectionPolicy: ReconnectionPolicy = .standard,
        heartbeatInterval: TimeInterval = 15,
        maxSubscriptions: Int = 50,
        maxPayloadSize: Int = 256 * 1024,
        defaultMessageTTL: TimeInterval? = 3600,
        compressionEnabled: Bool = false,
        offlineQueueConfig: OfflineQueueConfiguration = .default,
        deduplicationWindowSize: Int = 1000,
        deduplicationTTL: TimeInterval = 300,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        metricsDelegate: (any RealtimeMetricsDelegate)? = nil,

        // Protocol-specific (App Target can ignore these)
        clientId: String? = nil,
        mqttVersion: MQTTVersion? = nil,
        mqttCleanSession: Bool? = nil,
        mqttRetainSupported: Bool? = nil,
        mqttReceiveMaximum: UInt16? = nil,
        mqttSessionExpiryInterval: UInt32? = nil,
        mqttTopicAliasMaximum: UInt16? = nil,
        lastWillConfig: LastWillConfig? = nil,
        webSocketPath: String? = nil,
        webSocketSubprotocols: [String]? = nil,
        webSocketHeaders: [String: String]? = nil
    ) {
        self.transport = transport
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.authDelegate = authDelegate
        self.deviceInfo = deviceInfo
        self.networkMonitor = networkMonitor
        self.deviceTier = deviceTier
        self.performanceMonitor = performanceMonitor
        self.fallback = fallback
        self.pinnedPublicKeyHashes = pinnedPublicKeyHashes
        self.userId = userId
        self.reconnectionPolicy = reconnectionPolicy
        self.heartbeatInterval = heartbeatInterval
        self.maxSubscriptions = maxSubscriptions
        self.maxPayloadSize = maxPayloadSize
        self.defaultMessageTTL = defaultMessageTTL
        self.compressionEnabled = compressionEnabled
        self.offlineQueueConfig = offlineQueueConfig
        self.deduplicationWindowSize = deduplicationWindowSize
        self.deduplicationTTL = deduplicationTTL
        self.dateDecodingStrategy = dateDecodingStrategy
        self.keyDecodingStrategy = keyDecodingStrategy
        self.metricsDelegate = metricsDelegate
        self.clientId = clientId
        self.mqttVersion = mqttVersion
        self.mqttCleanSession = mqttCleanSession
        self.mqttRetainSupported = mqttRetainSupported
        self.mqttReceiveMaximum = mqttReceiveMaximum
        self.mqttSessionExpiryInterval = mqttSessionExpiryInterval
        self.mqttTopicAliasMaximum = mqttTopicAliasMaximum
        self.lastWillConfig = lastWillConfig
        self.webSocketPath = webSocketPath
        self.webSocketSubprotocols = webSocketSubprotocols
        self.webSocketHeaders = webSocketHeaders
    }
}

// MARK: - TransportType (Public)

/// Type de transport disponible.
///
/// L'App Target choisit le transport ici.
/// Changer de transport = changer cette valeur uniquement.
///
/// ```swift
/// RealtimeConfiguration(transport: .mqtt, ...)   // Production
/// RealtimeConfiguration(transport: .webSocket, ...)  // Alternative
/// RealtimeConfiguration(transport: .inMemory, ...)   // Tests / CI
/// ```
public enum TransportType: String, Sendable, CaseIterable {
    /// MQTT (protocole binaire, optimisé IoT). Recommandé pour la production.
    case mqtt

    /// WebSocket (bidirectionnel sur HTTP). Alternative à MQTT.
    case webSocket

    /// En mémoire. Pour les tests unitaires et les previews SwiftUI.
    case inMemory
}

// MARK: - TransportFallbackConfig (Public)

/// Configuration de fallback automatique entre transports.
///
/// Si le transport principal échoue après N tentatives,
/// le système essaie automatiquement le transport suivant dans la chaîne.
///
/// ```swift
/// TransportFallbackConfig(
///     chain: [.mqtt, .webSocket],
///     attemptsPerTransport: 3,
///     fallbackTimeout: 30
/// )
/// ```
public struct TransportFallbackConfig: Sendable {

    /// Chaîne de transports à essayer dans l'ordre.
    public let chain: [TransportType]

    /// Nombre de tentatives par transport avant de passer au suivant.
    public let attemptsPerTransport: Int

    /// Timeout total par transport (secondes).
    public let fallbackTimeout: TimeInterval

    public init(
        chain: [TransportType],
        attemptsPerTransport: Int = 3,
        fallbackTimeout: TimeInterval = 30
    ) {
        self.chain = chain
        self.attemptsPerTransport = attemptsPerTransport
        self.fallbackTimeout = fallbackTimeout
    }
}

// MARK: - ReconnectionPolicy (Public — moved to CoreKit in the prompt but defined here for now)

/// Politique de reconnexion avec exponential backoff + jitter.
///
/// ```swift
/// .standard    → usage normal (chat, marketplace)
/// .aggressive  → latence critique (ride tracking en cours)
/// .conservative → background, batterie faible
/// .disabled    → pas de reconnexion automatique
/// ```
public struct ReconnectionPolicy: Sendable {

    /// Nombre maximum de tentatives. `0` = infini.
    public let maxAttempts: Int

    /// Délai initial avant la première tentative (secondes).
    public let baseDelay: TimeInterval

    /// Délai maximum entre deux tentatives (secondes).
    public let maxDelay: TimeInterval

    /// Plage de jitter (ex: 0.0...0.5 = ajouter 0% à 50% du délai).
    public let jitterRange: ClosedRange<Double>

    /// Si la connexion tient plus longtemps que cette durée, le compteur reset.
    public let resetAfterConnectedFor: TimeInterval

    public init(
        maxAttempts: Int = 0,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        jitterRange: ClosedRange<Double> = 0.0...0.5,
        resetAfterConnectedFor: TimeInterval = 30.0
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterRange = jitterRange
        self.resetAfterConnectedFor = resetAfterConnectedFor
    }

    // MARK: - Presets

    /// Reconnexion standard (chat, marketplace, notifications).
    public static let standard = ReconnectionPolicy(
        maxAttempts: 0,         // infini
        baseDelay: 1.0,
        maxDelay: 60.0,
        jitterRange: 0.0...0.3
    )

    /// Reconnexion agressive (ride tracking actif).
    /// Délais courts, tentatives rapides.
    public static let aggressive = ReconnectionPolicy(
        maxAttempts: 0,
        baseDelay: 0.5,
        maxDelay: 15.0,
        jitterRange: 0.0...0.2
    )

    /// Reconnexion conservatrice (background, batterie faible).
    /// Délais longs pour économiser la batterie.
    public static let conservative = ReconnectionPolicy(
        maxAttempts: 10,
        baseDelay: 5.0,
        maxDelay: 300.0,        // 5 minutes max
        jitterRange: 0.0...0.5
    )

    /// Pas de reconnexion automatique.
    public static let disabled = ReconnectionPolicy(
        maxAttempts: 1,
        baseDelay: 0,
        maxDelay: 0,
        jitterRange: 0.0...0.0
    )
}

// MARK: - Stub Auth Delegate (Testing)

/// Stub d'auth delegate pour les tests avec InMemoryTransport.
struct StubAuthDelegate: RealtimeAuthDelegate {
    func realtimeClientNeedsToken() async throws -> RealtimeCredentials {
        RealtimeCredentials(
            token: "test-token",
            userId: "test-user",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    var tokenRefreshThreshold: TimeInterval { 60 }

    func realtimeClientDidFailAuthentication(error: RealtimeError) async {}
}

// MARK: - InMemoryOfflineQueue (Minimal — for assembly wiring)

/// Implémentation en mémoire minimale de l'offline queue.
///
/// Utilisée par défaut et dans les tests.
/// L'implémentation persistante (StorageKit) sera créée à l'étape 9.
final class InMemoryOfflineQueue: OfflineQueueProtocol, @unchecked Sendable {

    private var items: [OfflineQueueItem] = []
    private let lock = NSLock()
    private let maxSize: Int

    init(config: OfflineQueueConfiguration = .default) {
        self.maxSize = config.maxSize
    }

    func enqueue(_ item: OfflineQueueItem) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard items.count < maxSize else {
            throw RealtimeError.offlineQueueFull(currentSize: items.count, maxSize: maxSize)
        }
        items.append(item)
    }

    func flush(
        handler: @Sendable (OfflineQueueItem) async throws -> Bool
    ) async -> OfflineFlushResult {
        let startTime = Date()
        lock.lock()
        let snapshot = items
        items.removeAll()
        lock.unlock()

        var sent = 0
        var expired = 0
        var failed = 0
        var remaining: [OfflineQueueItem] = []

        for item in snapshot {
            if item.isExpired() {
                expired += 1
                continue
            }
            do {
                let success = try await handler(item)
                if success {
                    sent += 1
                } else {
                    failed += 1
                    remaining.append(item)
                }
            } catch {
                failed += 1
                remaining.append(item)
            }
        }

        // Re-enqueue les messages qui ont échoué.
        if !remaining.isEmpty {
            lock.lock()
            items.insert(contentsOf: remaining, at: 0)
            lock.unlock()
        }

        return OfflineFlushResult(
            sentCount: sent,
            expiredCount: expired,
            failedCount: failed,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    var pendingCount: Int {
        get async {
            lock.lock()
            defer { lock.unlock() }
            return items.count
        }
    }

    func pendingItems() async -> [OfflineQueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func clear() async {
        lock.lock()
        items.removeAll()
        lock.unlock()
    }

    func purgeExpired() async -> Int {
        lock.lock()
        let before = items.count
        items.removeAll { $0.isExpired() }
        let purged = before - items.count
        lock.unlock()
        return purged
    }

    func clear(for topic: RealtimeTopic) async {
        lock.lock()
        items.removeAll { $0.topic == topic }
        lock.unlock()
    }
}
