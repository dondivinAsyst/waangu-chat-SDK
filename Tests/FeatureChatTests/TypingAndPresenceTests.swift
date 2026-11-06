//
//  TypingAndPresenceTests.swift
//  FeatureChatTests
//
//  Harness 360 — matrice miroir : saisie (« écrit… ») et présence.
//  Les deux passent par leurs propres topics temps réel (PresenceRepository),
//  pas par le flux de synchronisation : un « écrit… » rejoué des minutes plus
//  tard serait faux. `TypingStore` n'a pas d'événement d'arrêt fiable — une
//  entrée expire si le pair cesse de la rafraîchir.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

// MARK: - TypingStore

@MainActor
final class TypingStoreTests: XCTestCase {

    private let clock = TestClock()

    private func makeStore() -> TypingStore {
        let clock = self.clock
        return TypingStore(now: { clock.now })
    }

    private func user(_ sender: String, in conversation: String, msg: String = "typing") -> TypingUser {
        TypingUser(name: sender, msg: msg, senderId: sender, conversationId: conversation, groupeId: conversation)
    }

    /// Un pair rafraîchit toutes les 3 s : une seule entrée, mise à jour.
    func test_repeatedTicks_keepOneEntry_andFollowTheLatestActivity() {
        let store = makeStore()

        store.set(user("aline", in: "c1"))
        store.set(user("aline", in: "c1", msg: "recordingVoice"))

        XCTAssertEqual(store.users(in: "c1").map(\.msg), ["recordingVoice"])
    }

    func test_typistsAreListedInTheOrderTheyStarted_perConversation() {
        let store = makeStore()

        store.set(user("aline", in: "c1"))
        store.set(user("bob", in: "c1"))
        store.set(user("chris", in: "c2"))

        XCTAssertEqual(store.users(in: "c1").map(\.senderId), ["aline", "bob"])
        XCTAssertEqual(store.users(in: "c2").map(\.senderId), ["chris"])
    }

    func test_clear_removesOnlyThatTypist() {
        let store = makeStore()
        store.set(user("aline", in: "c1"))
        store.set(user("bob", in: "c1"))

        store.clear(senderId: "aline", conversationId: "c1")

        XCTAssertEqual(store.users(in: "c1").map(\.senderId), ["bob"])
    }

    func test_lastTypistCleared_removesTheConversation() {
        let store = makeStore()
        store.set(user("aline", in: "c1"))

        store.clear(senderId: "aline", conversationId: "c1")

        XCTAssertNil(store.byConversation["c1"])
    }

    func test_tickWithoutConversationOrSender_isIgnored() {
        let store = makeStore()

        store.set(user("", in: "c1"))
        store.set(user("aline", in: ""))

        XCTAssertTrue(store.byConversation.isEmpty)
    }

    func test_clearAll_wipesEverything() {
        let store = makeStore()
        store.set(user("aline", in: "c1"))
        store.set(user("bob", in: "c2"))

        store.clearAll()

        XCTAssertTrue(store.byConversation.isEmpty)
    }

    /// Une salle ouverte en pleine saisie affiche l'indicateur tout de suite.
    func test_stream_startsWithTheCurrentTypists() async {
        let store = makeStore()
        store.set(user("aline", in: "c1"))

        var iterator = store.stream(for: "c1").makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first?.map(\.senderId), ["aline"])
    }

    /// Sans rafraîchissement, l'entrée disparaît après le TTL — sinon une seule
    /// frappe laissait « écrit… » à l'écran pour toujours.
    func test_entryExpires_whenThePeerStopsRefreshing() async {
        let store = makeStore()
        store.set(user("aline", in: "c1"))

        clock.advance(by: TypingStore.ttl + 1)

        let gone = await waitUntil { store.users(in: "c1").isEmpty }
        XCTAssertTrue(gone, "entry should be swept after the TTL")
    }

    func test_refreshedEntry_survivesPastTheFirstDeadline() async {
        let store = makeStore()
        store.set(user("aline", in: "c1"))

        clock.advance(by: TypingStore.ttl - 1)
        store.set(user("aline", in: "c1"))
        clock.advance(by: 2)
        // Laisse passer au moins un balayage.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertEqual(store.users(in: "c1").map(\.senderId), ["aline"])
    }
}

// MARK: - Flux temps réel

final class PresenceFeedTests: XCTestCase {

    private let me = "me"

    // MARK: Saisie

    @MainActor
    func test_peerTypingTick_appearsUnderTheLocalConversationId() async throws {
        let (store, local) = try await seedConversation(serverId: "srv-\(UUID().uuidString)")
        // La base de test survit d'un lancement à l'autre : un pair inconnu d'elle.
        let peer = "peer-\(UUID().uuidString)"
        let realtime = ScriptedRealtimeClient(payloads: [
            ["eventType": "TYPING", "payload": ["conversationId": local.serverId!, "senderId": peer,
                                                "senderPhone": "+25779000000", "type": "TEXT"]]
        ])

        try await repository(realtime: realtime, database: store).runTypingFeed()

        let typists = TypingStore.shared.users(in: local.id)
        XCTAssertEqual(typists.map(\.senderId), [peer])
        XCTAssertEqual(typists.first?.msg, "typing")
        XCTAssertEqual(typists.first?.name, "+25779000000", "phone is the fallback name without a contact")
        TypingStore.shared.clear(senderId: peer, conversationId: local.id)
    }

    /// Le nom du carnet d'adresses l'emporte sur le numéro envoyé par le serveur.
    @MainActor
    func test_typingName_comesFromTheContactBookWhenKnown() async throws {
        let (store, local) = try await seedConversation()
        let peer = "peer-\(UUID().uuidString)"
        try await store.save(ContactModel(userId: peer, phone: "+25779111111", name: "Aline"))
        let realtime = ScriptedRealtimeClient(payloads: [
            ["conversationId": local.id, "senderId": peer, "senderPhone": "+25779111111"]
        ])

        try await repository(realtime: realtime, database: store).runTypingFeed()

        XCTAssertEqual(TypingStore.shared.users(in: local.id).first?.name, "Aline")
        TypingStore.shared.clear(senderId: peer, conversationId: local.id)
    }

    /// Le nom vient du contact par son id, même quand la charge porte un autre
    /// numéro que celui enregistré (B45).
    @MainActor
    func test_typingName_resolvesByUserId_evenWithAnotherPhoneInThePayload() async throws {
        let (store, local) = try await seedConversation()
        let peer = "peer-\(UUID().uuidString)"
        try await store.save(ContactModel(userId: peer, phone: "+25779333333", name: "Chris"))
        let realtime = ScriptedRealtimeClient(payloads: [
            ["conversationId": local.id, "senderId": peer, "userName": "+25779000000"]
        ])

        try await repository(realtime: realtime, database: store).runTypingFeed()

        XCTAssertEqual(TypingStore.shared.users(in: local.id).first?.name, "Chris")
        TypingStore.shared.clear(senderId: peer, conversationId: local.id)
    }

    @MainActor
    func test_audioTick_isShownAsRecordingVoice() async throws {
        let conversation = "c-\(UUID().uuidString)"
        let realtime = ScriptedRealtimeClient(payloads: [
            ["conversationId": conversation, "senderId": "peer-1", "type": "AUDIO"]
        ])

        try await repository(realtime: realtime).runTypingFeed()

        let typist = TypingStore.shared.users(in: conversation).first
        XCTAssertEqual(typist?.msg, "recordingVoice")
        XCTAssertEqual(typist?.messageType, .AUDIO)
        TypingStore.shared.clear(senderId: "peer-1", conversationId: conversation)
    }

    @MainActor
    func test_ownEcho_andOtherEventTypes_areDropped() async throws {
        let conversation = "c-\(UUID().uuidString)"
        let realtime = ScriptedRealtimeClient(payloads: [
            ["conversationId": conversation, "senderId": me],
            ["eventType": "MESSAGE", "payload": ["conversationId": conversation, "senderId": "peer-1"]],
            ["senderId": "peer-1"]
        ])

        try await repository(realtime: realtime).runTypingFeed()

        XCTAssertTrue(TypingStore.shared.users(in: conversation).isEmpty)
    }

    @MainActor
    func test_idleTick_clearsTheIndicatorWithoutWaitingForTheTTL() async throws {
        let conversation = "c-\(UUID().uuidString)"
        let realtime = ScriptedRealtimeClient(payloads: [
            ["conversationId": conversation, "senderId": "peer-1", "event": "typing"],
            ["conversationId": conversation, "senderId": "peer-1", "event": "idle"]
        ])

        try await repository(realtime: realtime).runTypingFeed()

        XCTAssertTrue(TypingStore.shared.users(in: conversation).isEmpty)
    }

    // MARK: Présence

    func test_peerPresence_isStored_andOwnPresenceIsIgnored() async throws {
        let presence = UserPresenceStore()
        let realtime = ScriptedRealtimeClient(payloads: [
            ["payload": ["userId": "peer-1", "status": "online"]],
            ["userId": me, "status": "BUSY"],
            ["userId": "peer-2", "status": "AWAY"]
        ])

        try await repository(realtime: realtime, presence: presence).runPresenceFeed()

        XCTAssertEqual(presence.presence(for: "peer-1")?.status, .online, "status is case-insensitive")
        XCTAssertNil(presence.presence(for: me))
        XCTAssertNil(presence.presence(for: "peer-2"), "unknown status is dropped")
    }

    /// Passé hors ligne : l'heure de dernière connexion est gardée sur le
    /// contact. La colonne s'appelle `user_id` — filtrer sur `userId` faisait
    /// échouer la requête en silence (B45).
    func test_peerGoingOffline_recordsLastSeenOnTheContact() async throws {
        let (store, _) = try await seedConversation()
        let peer = "peer-\(UUID().uuidString)"
        try await store.save(ContactModel(userId: peer, phone: "+25779222222", name: "Bob"))
        let realtime = ScriptedRealtimeClient(payloads: [
            ["userId": peer, "status": "OFFLINE", "lastSeen": "2026-10-07T12:00:00Z"]
        ])

        try await repository(realtime: realtime, database: store).runPresenceFeed()

        let contacts = try await store.fetch(ContactModel.self,
                                             query: QuerySpec(filter: FilterSpec("user_id == %@", .string(peer))))
        XCTAssertEqual(contacts.first?.lastSeenAt, ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z"))
    }

    // MARK: Outils

    private func repository(
        realtime: ScriptedRealtimeClient,
        database: (any DatabaseRepositoryProtocol)? = nil,
        presence: UserPresenceStore = UserPresenceStore()
    ) -> PresenceRepository {
        let me = self.me
        return PresenceRepository(realtime: realtime, database: database, presenceStore: presence,
                                  currentUserId: { me })
    }

    private func seedConversation(
        serverId: String? = nil
    ) async throws -> (any DatabaseRepositoryProtocol, ConversationModel) {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", serverId: serverId, type: .direct)
        try await store.save(conversation)
        return (store, conversation)
    }
}

// MARK: - Doublures

/// Horloge que le test fait avancer.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_791_000_000)
    var now: Date { lock.withLock { _now } }
    func advance(by seconds: TimeInterval) { lock.withLock { _now.addTimeInterval(seconds) } }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 4, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
}

/// Client temps réel dont chaque souscription rejoue des charges JSON puis se termine.
private final class ScriptedRealtimeClient: RealtimeClientProtocol, @unchecked Sendable {
    private let payloads: [[String: Any]]

    init(payloads: [[String: Any]]) { self.payloads = payloads }

    var connectionState: RealtimeConnectionState { get async { .connected } }
    func observeConnectionState() -> AsyncStream<RealtimeConnectionState> { AsyncStream { $0.finish() } }
    func connect() async throws {}
    func disconnect(reason: DisconnectReason, flushQueue: Bool) async throws {}

    func subscribe<T: Decodable & Sendable>(
        to topic: RealtimeTopic,
        as type: T.Type,
        buffering: RealtimeBufferingPolicy,
        qos: RealtimeQoS
    ) async throws -> (stream: AsyncStream<T>, token: any RealtimeSubscriptionToken) {
        let decoded = try payloads.map { try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: $0)) }
        let stream = AsyncStream<T> { continuation in
            decoded.forEach { continuation.yield($0) }
            continuation.finish()
        }
        return (stream, ScriptedToken(topic: topic))
    }

    func publish<T: Encodable & Sendable>(_ payload: T, to topic: RealtimeTopic, qos: RealtimeQoS,
                                          priority: MessagePriority) async throws {}

    func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ payload: Request, to topic: RealtimeTopic, replyOn: RealtimeTopic,
        as responseType: Response.Type, timeout: TimeInterval
    ) async throws -> Response {
        throw ChatSendPathFakeError.unexpectedCall
    }

    func publishPresence(_ state: PresenceState, to topic: RealtimeTopic) async throws {}
    func observePresence(on topic: RealtimeTopic) -> AsyncStream<PresenceInfo> { AsyncStream { $0.finish() } }
    func cancelSubscription(_ token: any RealtimeSubscriptionToken) async {}
    func cancelAllSubscriptions(forFeature feature: String) async {}
    var activeSubscriptionCount: Int { get async { 0 } }
    func isSubscribed(to topic: RealtimeTopic) async -> Bool { false }
    func subscriptionDiagnostics() async -> [RealtimeSubscriptionDiagnostic] { [] }
    func register(_ registrations: [TopicRegistration]) async {}

    let offlineQueue: any OfflineQueueProtocol = EmptyOfflineQueue()
}

private final class ScriptedToken: RealtimeSubscriptionToken, @unchecked Sendable {
    let id = UUID()
    let topic: RealtimeTopic
    let feature: String? = nil
    init(topic: RealtimeTopic) { self.topic = topic }
    var isActive: Bool { get async { false } }
    func cancel() async {}
}
