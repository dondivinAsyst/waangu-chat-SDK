//
//  LateResponseAfterSessionChangeTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, F-04 — une réponse serveur arrivée après une
//  déconnexion ou un changement de compte ne doit rien écrire : la purge de
//  déconnexion est ponctuelle, elle ne rattrape pas une écriture tardive.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class LateResponseAfterSessionChangeTests: XCTestCase {

    private let peer = "peer-1"
    private let serverTime = Date(timeIntervalSince1970: 1_791_000_000)

    func test_inboxSummary_arrivingAfterLogout_writesNothing() async throws {
        let (store, conversationId, messageId) = try await makeScenario()
        let session = SessionBox("me")

        let completed = await pull(into: store, conversationId: conversationId, messageId: messageId,
                                   session: session, duringRequest: { session.set("") })

        let stored = try await store.fetchOne(MessageModel.self, id: messageId)
        XCTAssertNil(stored, "Late response after logout must not repopulate the purged database")
        XCTAssertFalse(completed)
    }

    func test_inboxSummary_arrivingAfterAccountSwitch_writesNothing() async throws {
        let (store, conversationId, messageId) = try await makeScenario()
        let session = SessionBox("me")

        _ = await pull(into: store, conversationId: conversationId, messageId: messageId,
                       session: session, duringRequest: { session.set("someone-else") })

        let stored = try await store.fetchOne(MessageModel.self, id: messageId)
        XCTAssertNil(stored, "Late response for account A must not land in account B's database")
    }

    /// Control: nothing changed during the request, so the summary is stored as before.
    func test_inboxSummary_withUnchangedSession_isStored() async throws {
        let (store, conversationId, messageId) = try await makeScenario()
        let session = SessionBox("me")

        _ = await pull(into: store, conversationId: conversationId, messageId: messageId,
                       session: session, duringRequest: {})

        let stored = try await store.fetchOne(MessageModel.self, id: messageId)
        XCTAssertNotNil(stored)
    }

    // MARK: - Flux temps réel

    /// Un événement livré après le départ du compte propriétaire n'est pas appliqué,
    /// ni aucun des suivants : le flux est abandonné.
    func test_realtimeStream_dropsEventsOnceTheOwnerIsGone() async {
        let session = SessionBox("me")
        let applied = Applied()
        let stream = AsyncStream<ChatSyncEventDTO> { continuation in
            for id in ["e1", "e2", "e3"] {
                continuation.yield(ChatSyncEventDTO(type: "message", referenceId: id, conversationId: "c",
                                                    payload: nil, at: 0))
            }
            continuation.finish()
        }

        await ChatFeature.apply(stream, ownedBy: "me", currentUserId: { session.value }) { event in
            await applied.add(event.referenceId ?? "")
            if event.referenceId == "e1" { session.set("") } // logout lands after the first event
        }

        let ids = await applied.ids
        XCTAssertEqual(ids, ["e1"], "Nothing may be applied once the owning account has left")
    }

    func test_realtimeStream_appliesEverything_whileTheOwnerStays() async {
        let applied = Applied()
        let stream = AsyncStream<ChatSyncEventDTO> { continuation in
            for id in ["e1", "e2"] {
                continuation.yield(ChatSyncEventDTO(type: "message", referenceId: id, conversationId: "c",
                                                    payload: nil, at: 0))
            }
            continuation.finish()
        }

        await ChatFeature.apply(stream, ownedBy: "me", currentUserId: { "me" }) { event in
            await applied.add(event.referenceId ?? "")
        }

        let ids = await applied.ids
        XCTAssertEqual(ids, ["e1", "e2"])
    }

    // MARK: - Outils

    private func makeScenario() async throws -> (any DatabaseRepositoryProtocol, String, String) {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        return (store, conversation.id, "msg-\(UUID().uuidString)")
    }

    private func pull(
        into store: any DatabaseRepositoryProtocol,
        conversationId: String,
        messageId: String,
        session: SessionBox,
        duringRequest: @escaping @Sendable () -> Void
    ) async -> Bool {
        let contentJSON = String(data: try! JSONSerialization.data(withJSONObject: ["text": "hello"]), encoding: .utf8)!
        let lastMessage: [String: Any] = ["codeMessage": messageId, "senderId": peer, "senderName": "Peer",
                                          "conversationId": conversationId, "content": contentJSON,
                                          "typeMessage": "TEXT", "timestamp": serverTime.timeIntervalSince1970]
        let summary: [String: Any] = ["id": conversationId, "type": "DIRECT", "participantIds": ["me", peer],
                                      "lastMessage": lastMessage, "unreadCount": 0,
                                      "updatedAt": serverTime.timeIntervalSince1970, "status": "ACTIVE"]
        let body = try! JSONSerialization.data(withJSONObject: ["conversations": [summary], "syncTimestamp": 0])
        return await ChatSyncDelegate(fieldCrypto: PassthroughCrypto(), currentUserId: { session.value })
            .pullInboxSummary(apiClient: SlowStubClient(body: body, onRequest: duringRequest), database: store)
    }
}

private actor Applied {
    private(set) var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}

private final class SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String
    init(_ initial: String) { current = initial }
    var value: String { lock.lock(); defer { lock.unlock() }; return current }
    func set(_ new: String) { lock.lock(); current = new; lock.unlock() }
}

/// Answers with a fixed body, after running `onRequest` — the moment a logout can land.
private final class SlowStubClient: APIClientProtocol, @unchecked Sendable {
    private let body: Data
    private let onRequest: @Sendable () -> Void
    init(body: Data, onRequest: @escaping @Sendable () -> Void) { self.body = body; self.onRequest = onRequest }

    var isConnected: Bool { get async { true } }
    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        onRequest()
        return try JSONDecoder().decode(T.self, from: body)
    }
    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}

private struct PassthroughCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
