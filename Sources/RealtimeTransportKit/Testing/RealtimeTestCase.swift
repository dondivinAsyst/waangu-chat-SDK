//// MARK: - RealtimeKit/Testing/RealtimeTestCase.swift
////
//// Module  : RealtimeKit (testing only)
//// Rôle    : Infrastructure de test pour le système temps réel.
////           Trois composants :
////
////   ChaosTransport    → simule des conditions dégradées (latence, perte, déconnexion)
////   RecordingTransport→ enregistre tous les échanges pour assertions détaillées
////   RealtimeTestCase  → base class XCTestCase avec helpers
//
//import Foundation
//import CoreKit
//import XCTest
//
//// MARK: ─────────────────────────────────────────────────────────────
//// MARK: - ChaosTransport
//// MARK: ─────────────────────────────────────────────────────────────
//
///// Transport qui simule des conditions réseau dégradées.
/////
///// Utile pour tester la résilience : reconnexion automatique,
///// offline queue, déduplication, backpressure.
/////
///// ```swift
///// let chaos = ChaosTransport(config: .init(
/////     latencyRange: 0.1...0.5,    // 100-500ms de latence aléatoire
/////     messageDropRate: 0.1,       // 10% des messages droppés
/////     disconnectAfter: 5          // déconnexion après 5 messages
///// ))
///// ```
//actor ChaosTransport: RealtimeTransport {
//
//    nonisolated let transportName: String = "Chaos"
//    nonisolated let transportType: RealtimeTransportType = .inMemory
//
//    // MARK: - Config
//
//    struct Config: Sendable {
//        let latencyRange: ClosedRange<TimeInterval>
//        let messageDropRate: Double
//        let disconnectAfter: Int?
//        let reconnectDelay: TimeInterval
//
//        static let noisy = Config(
//            latencyRange: 0.05...0.3,
//            messageDropRate: 0.05,
//            disconnectAfter: nil,
//            reconnectDelay: 1.0
//        )
//
//        static let severe = Config(
//            latencyRange: 0.5...2.0,
//            messageDropRate: 0.3,
//            disconnectAfter: 10,
//            reconnectDelay: 3.0
//        )
//    }
//
//    // MARK: - State
//
//    private let config: Config
//    private var _isConnected: Bool = false
//    private var messageCount: Int = 0
//
//    private var connectionContinuation: AsyncStream<TransportConnectionEvent>.Continuation?
//    private var messageContinuation: AsyncStream<RawTransportMessage>.Continuation?
//
//    private(set) var droppedMessageCount: Int = 0
//    private(set) var totalLatency: TimeInterval = 0
//
//    init(config: Config = .noisy) {
//        self.config = config
//    }
//
//    // MARK: - RealtimeTransport
//
//    var isConnected: Bool { get async { _isConnected } }
//
//    func connect(config transportConfig: RealtimeTransportConfig) async throws {
//        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.1...0.5) * 1_000_000_000))
//        _isConnected = true
//        connectionContinuation?.yield(.connected)
//    }
//
//    func disconnect(reason: DisconnectReason) async throws {
//        _isConnected = false
//        connectionContinuation?.yield(.disconnected(error: nil, isRecoverable: false))
//    }
//
//    func connectionStateStream() -> AsyncStream<TransportConnectionEvent> {
//        connectionContinuation?.finish()
//        let (stream, cont) = AsyncStream<TransportConnectionEvent>.makeStream()
//        connectionContinuation = cont
//        return stream
//    }
//
//    func subscribe(topic: String, qos: RealtimeQoS) async throws {
//        guard _isConnected else { throw RealtimeError.notConnected }
//    }
//
//    func unsubscribe(topic: String) async throws {}
//
//    func publish(data: Data, to topic: String, qos: RealtimeQoS, messageId: MessageID) async throws {
//        guard _isConnected else { throw RealtimeError.notConnected }
//
//        // Latence simulée
//        let latency = TimeInterval.random(in: config.latencyRange)
//        totalLatency += latency
//        try? await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000))
//
//        // Drop aléatoire
//        if Double.random(in: 0...1) < config.messageDropRate {
//            droppedMessageCount += 1
//            return
//        }
//
//        // Déconnexion après N messages
//        messageCount += 1
//        if let disconnectAfter = config.disconnectAfter, messageCount >= disconnectAfter {
//            messageCount = 0
//            _isConnected = false
//            connectionContinuation?.yield(
//                .disconnected(error: "ChaosTransport: planned disconnect", isRecoverable: true)
//            )
//        }
//    }
//
//    func incomingMessages() -> AsyncStream<RawTransportMessage> {
//        messageContinuation?.finish()
//        let (stream, cont) = AsyncStream<RawTransportMessage>.makeStream()
//        messageContinuation = cont
//        return stream
//    }
//
//    func updateHeartbeatInterval(_ interval: TimeInterval?) async {}
//
//    // MARK: - Chaos API
//
//    /// Injecte un message entrant (avec latence simulée).
//    func injectMessage(topic: String, payload: Data) async {
//        let latency = TimeInterval.random(in: config.latencyRange)
//        try? await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000))
//
//        if Double.random(in: 0...1) >= config.messageDropRate {
//            messageContinuation?.yield(
//                RawTransportMessage(topic: topic, payload: payload, receivedAt: Date())
//            )
//        }
//    }
//
//    /// Force une déconnexion inattendue.
//    func triggerDisconnect(recoverable: Bool = true) {
//        _isConnected = false
//        connectionContinuation?.yield(
//            .disconnected(error: "ChaosTransport: forced disconnect", isRecoverable: recoverable)
//        )
//    }
//
//    var averageLatencyMs: Double {
//        messageCount > 0 ? (totalLatency / Double(messageCount)) * 1000 : 0
//    }
//}
//
//// MARK: ─────────────────────────────────────────────────────────────
//// MARK: - RecordingTransport
//// MARK: ─────────────────────────────────────────────────────────────
//
///// Transport qui enregistre tous les échanges pour assertions précises.
/////
///// ```swift
///// let recording = RecordingTransport()
///// // ... faire des opérations ...
/////
///// // Assertions
///// XCTAssertEqual(recording.publishedMessages.count, 3)
///// XCTAssertEqual(recording.subscribedTopics, ["chat/1/messages"])
///// let msg = try recording.publishedMessages[0].decode(as: ChatMessage.self)
///// XCTAssertEqual(msg.text, "Hello")
///// ```
//actor RecordingTransport: RealtimeTransport {
//
//    nonisolated let transportName: String = "Recording"
//    nonisolated let transportType: RealtimeTransportType = .inMemory
//
//    // MARK: - Recording
//
//    private(set) var publishedMessages: [RecordedMessage] = []
//    private(set) var subscribedTopics: [String] = []
//    private(set) var unsubscribedTopics: [String] = []
//    private(set) var connectionEvents: [String] = []
//    private(set) var connectCallCount: Int = 0
//    private(set) var disconnectCallCount: Int = 0
//
//    // MARK: - State
//
//    private var _isConnected: Bool = false
//    private var connectionContinuation: AsyncStream<TransportConnectionEvent>.Continuation?
//    private var messageContinuation: AsyncStream<RawTransportMessage>.Continuation?
//
//    var isConnected: Bool { _isConnected }
//
//    // MARK: - RealtimeTransport
//
//    func connect(config: RealtimeTransportConfig) async throws {
//        connectCallCount += 1
//        _isConnected = true
//        connectionEvents.append("connect")
//        connectionContinuation?.yield(.connected)
//    }
//
//    func disconnect(reason: DisconnectReason) async throws {
//        disconnectCallCount += 1
//        _isConnected = false
//        connectionEvents.append("disconnect(\(reason))")
//        connectionContinuation?.yield(.disconnected(error: nil, isRecoverable: false))
//    }
//
//    func connectionStateStream() -> AsyncStream<TransportConnectionEvent> {
//        connectionContinuation?.finish()
//        let (stream, cont) = AsyncStream<TransportConnectionEvent>.makeStream()
//        connectionContinuation = cont
//        return stream
//    }
//
//    func subscribe(topic: String, qos: RealtimeQoS) async throws {
//        subscribedTopics.append(topic)
//    }
//
//    func unsubscribe(topic: String) async throws {
//        unsubscribedTopics.append(topic)
//    }
//
//    func publish(data: Data, to topic: String, qos: RealtimeQoS, messageId: MessageID) async throws {
//        publishedMessages.append(RecordedMessage(
//            topic: topic, data: data, qos: qos, messageId: messageId, timestamp: Date()
//        ))
//    }
//
//    func incomingMessages() -> AsyncStream<RawTransportMessage> {
//        messageContinuation?.finish()
//        let (stream, cont) = AsyncStream<RawTransportMessage>.makeStream()
//        messageContinuation = cont
//        return stream
//    }
//
//    func updateHeartbeatInterval(_ interval: TimeInterval?) async {}
//
//    // MARK: - Injection API
//
//    func simulateIncoming(topic: String, payload: Data) {
//        messageContinuation?.yield(
//            RawTransportMessage(topic: topic, payload: payload, receivedAt: Date())
//        )
//    }
//
//    // MARK: - Reset
//
//    func reset() {
//        publishedMessages.removeAll()
//        subscribedTopics.removeAll()
//        unsubscribedTopics.removeAll()
//        connectionEvents.removeAll()
//        connectCallCount = 0
//        disconnectCallCount = 0
//    }
//}
//
//// MARK: ─────────────────────────────────────────────────────────────
//// MARK: - RealtimeTestCase
//// MARK: ─────────────────────────────────────────────────────────────
//
///// Base class pour les tests unitaires du système temps réel.
/////
///// Fournit un client pré-connecté et des helpers pour les assertions.
/////
///// ```swift
///// class ChatRepositoryTests: RealtimeTestCase {
/////
/////     var chatRepository: ChatRepository!
/////
/////     override func setUp() async throws {
/////         try await super.setUp()
/////         chatRepository = ChatRepository(
/////             realtime: realtimeClient,
/////             database: mockDatabase,
/////             currentUserId: "user-1"
/////         )
/////     }
/////
/////     func testSendMessage() async throws {
/////         let message = ChatMessage(conversationId: UUID().uuidString.lowercased(), senderId: "user-1", text: "Hi")
/////         try await chatRepository.sendMessage(message)
/////         let published = await inMemoryTransport.publishedMessages
/////         XCTAssertEqual(published.count, 1)
/////     }
///// }
///// ```
//open class RealtimeTestCase: XCTestCase {
//
//    // MARK: - Test Infrastructure
//
//    public var realtimeClient: (any RealtimeClientProtocol)!
//    public var inMemoryTransport: InMemoryTransport?
//
//    // MARK: - Setup / Teardown
//
//    open override func setUp() async throws {
//        try await super.setUp()
//        let (client, transport) = RealtimeAssembly.makeInMemory()
//        self.realtimeClient = client
//        self.inMemoryTransport = transport
//        try await realtimeClient.connect()
//    }
//
//    open override func tearDown() async throws {
//        try? await realtimeClient.disconnect(reason: .userInitiated, flushQueue: false)
//        realtimeClient = nil
//        inMemoryTransport = nil
//        try await super.tearDown()
//    }
//
//    // MARK: - Helpers
//
//    /// Attend qu'un stream émette un élément, avec timeout.
//    public func awaitFirst<T: Sendable>(
//        from stream: AsyncStream<T>,
//        timeout: TimeInterval = 2.0,
//        file: StaticString = #file,
//        line: UInt = #line
//    ) async throws -> T {
//        try await withThrowingTaskGroup(of: T.self) { group in
//            group.addTask {
//                for await value in stream { return value }
//                throw XCTestError(.failureWhileWaiting)
//            }
//            group.addTask {
//                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
//                throw XCTestError(.timeoutWhileWaiting)
//            }
//            guard let result = try await group.next() else {
//                throw XCTestError(.failureWhileWaiting)
//            }
//            group.cancelAll()
//            return result
//        }
//    }
//
//    /// Simule un message JSON entrant et attend sa réception.
//    public func simulateAndReceive<T: Codable & Sendable>(
//        _ value: T,
//        on topic: RealtimeTopic,
//        as type: T.Type,
//        timeout: TimeInterval = 2.0
//    ) async throws -> T {
//        let data = try JSONEncoder().encode(value)
//        let (stream, _) = try await realtimeClient.subscribe(
//            to: topic, as: type, buffering: .unbounded, qos: .atLeastOnce
//        )
//        await inMemoryTransport.simulateIncoming(
//            topic: topic.path, payload: data
//        )
//        return try await awaitFirst(from: stream, timeout: timeout)
//    }
//
//    /// Vérifie le nombre de messages publiés.
//    public func assertPublishedCount(
//        _ count: Int,
//        file: StaticString = #file,
//        line: UInt = #line
//    ) async {
//        let published = await inMemoryTransport.publishedMessages
//        XCTAssertEqual(published.count, count, file: file, line: line)
//    }
//}
