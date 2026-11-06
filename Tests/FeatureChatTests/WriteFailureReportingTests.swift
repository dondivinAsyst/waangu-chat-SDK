//
//  WriteFailureReportingTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, N-02 — `ChatSyncDelegate.applyEvent` dit si une écriture a été
//  refusée, au lieu de l'avaler comme `processEvent`.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class WriteFailureReportingTests: XCTestCase {

    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func seededPendingMessage(in store: any DatabaseRepositoryProtocol) async throws -> MessageModel {
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let message = MessageModel(conversationId: conversation.id, senderId: "me", senderName: "Me",
                                   content: .text("hello"), timestamp: Date(), deliveryStatus: .pending)
        try await store.save(message)
        return message
    }

    private func ack(for message: MessageModel) -> ChatSyncEventDTO {
        ChatSyncEventDTO(type: "modify_ack", referenceId: message.id, conversationId: message.conversationId,
                         payload: nil, at: Date().timeIntervalSince1970)
    }

    private func delegate() -> ChatSyncDelegate {
        ChatSyncDelegate(fieldCrypto: PassthroughCrypto(), currentUserId: { "me" })
    }

    func test_applyEvent_reportsFailed_whenTheWriteIsRefused() async throws {
        let store = await makeStore()
        let message = try await seededPendingMessage(in: store)
        let refusing = RefusingMessageWrites(base: store)

        let outcome = await delegate().applyEvent(ack(for: message), database: refusing)

        guard case .failed = outcome else { return XCTFail("Expected .failed, got \(outcome)") }
        let stored = try await store.fetchOne(MessageModel.self, id: message.id)
        XCTAssertEqual(stored?.deliveryStatus, .pending, "The refused write must leave the old state")
    }

    func test_applyEvent_reportsApplied_andStores_whenTheWriteSucceeds() async throws {
        let store = await makeStore()
        let message = try await seededPendingMessage(in: store)

        let outcome = await delegate().applyEvent(ack(for: message), database: store)

        XCTAssertEqual(outcome, .applied)
        let stored = try await store.fetchOne(MessageModel.self, id: message.id)
        XCTAssertEqual(stored?.deliveryStatus, .sent)
    }

    // MARK: - Live events (N-02)

    private actor Refusals {
        private(set) var reasons: [String] = []
        func record(_ reason: String) { reasons.append(reason) }
    }

    func test_applyLiveEvent_reportsARefusedWrite_toTheRecoveryHook() async throws {
        let store = await makeStore()
        let message = try await seededPendingMessage(in: store)
        let refusals = Refusals()

        await ChatFeature.applyLiveEvent(ack(for: message), using: delegate(),
                                         database: RefusingMessageWrites(base: store)) { await refusals.record($0) }

        let reasons = await refusals.reasons
        XCTAssertEqual(reasons.count, 1)
        XCTAssertFalse(reasons[0].isEmpty)
    }

    func test_applyLiveEvent_staysQuiet_whenTheWriteSucceeds() async throws {
        let store = await makeStore()
        let message = try await seededPendingMessage(in: store)
        let refusals = Refusals()

        await ChatFeature.applyLiveEvent(ack(for: message), using: delegate(), database: store) { await refusals.record($0) }

        let reasons = await refusals.reasons
        XCTAssertTrue(reasons.isEmpty)
    }

    // MARK: - F-13 scrub of rows saved before

    private func freshDefaults() -> UserDefaults {
        let suite = "ScrubTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func test_scrub_clearsLegacyPlaintext_encryptsPreviews_leavesEncryptedOnesAlone_andRunsOnce() async throws {
        let store = await makeStore()
        let crypto = ScrubCrypto()
        let defaults = freshDefaults()
        let legacy = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct,
                                       lastMessageText: "plain preview", lastMessageSenderName: "Alice")
        let modern = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct,
                                       lastMessageText: crypto.encrypt("already"), lastMessageSenderName: crypto.encrypt("Bob"))
        try await store.save(legacy)
        try await store.save(modern)
        let message = MessageModel(conversationId: legacy.id, senderId: "peer", senderName: "Peer",
                                   content: .text(crypto.encrypt("hello")), searchText: "legacy plaintext",
                                   timestamp: Date(), deliveryStatus: .delivered)
        try await store.save(message)

        await ChatFeature.scrubLegacyPlaintext(database: store, crypto: crypto, defaults: defaults)

        let scrubbed = try await store.fetchOne(MessageModel.self, id: message.id)
        XCTAssertNil(scrubbed?.searchText)
        let legacyRow = try await store.fetchOne(ConversationModel.self, id: legacy.id)
        XCTAssertEqual(legacyRow?.lastMessageText, crypto.encrypt("plain preview"))
        XCTAssertEqual(legacyRow?.lastMessageSenderName, crypto.encrypt("Alice"))
        let modernRow = try await store.fetchOne(ConversationModel.self, id: modern.id)
        XCTAssertEqual(modernRow?.lastMessageText, crypto.encrypt("already"), "An encrypted value is not encrypted twice")
        XCTAssertTrue(defaults.bool(forKey: ChatFeature.legacyPlaintextScrubKey))

        // Once per install: a plain row that shows up afterwards is not touched again.
        let late = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct, lastMessageText: "late plain")
        try await store.save(late)
        await ChatFeature.scrubLegacyPlaintext(database: store, crypto: crypto, defaults: defaults)
        let lateRow = try await store.fetchOne(ConversationModel.self, id: late.id)
        XCTAssertEqual(lateRow?.lastMessageText, "late plain")
    }

    func test_scrub_leavesTheFlagUnset_whenASaveIsRefused_soTheNextLaunchRetries() async throws {
        let store = await makeStore()
        let defaults = freshDefaults()
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let message = MessageModel(conversationId: conversation.id, senderId: "peer", senderName: "Peer",
                                   content: .text("x"), searchText: "legacy plaintext",
                                   timestamp: Date(), deliveryStatus: .delivered)
        try await store.save(message)

        await ChatFeature.scrubLegacyPlaintext(database: RefusingMessageWrites(base: store),
                                               crypto: ScrubCrypto(), defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: ChatFeature.legacyPlaintextScrubKey))
        let stored = try await store.fetchOne(MessageModel.self, id: message.id)
        XCTAssertEqual(stored?.searchText, "legacy plaintext")
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

/// La vraie base, sauf que toute écriture d'un message est refusée.
private actor RefusingMessageWrites: DatabaseRepositoryProtocol {
    let base: any DatabaseRepositoryProtocol
    struct Refused: Error {}
    init(base: any DatabaseRepositoryProtocol) { self.base = base }

    func save<T: Storable>(_ entity: T) async throws {
        if entity is MessageModel { throw Refused() }
        try await base.save(entity)
    }
    func saveAll<T: Storable>(_ entities: [T]) async throws { for e in entities { try await save(e) } }
    func fetch<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> [T] { try await base.fetch(type, query: query) }
    func fetchOne<T: Storable>(_ type: T.Type, id: T.ID) async throws -> T? { try await base.fetchOne(type, id: id) }
    func count<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> Int { try await base.count(type, query: query) }
    func delete<T: Storable>(_ type: T.Type, id: T.ID) async throws { try await base.delete(type, id: id) }
    func deleteAll<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws { try await base.deleteAll(type, query: query) }
    func withTransaction<R: Sendable>(_ block: @Sendable () async throws -> R) async throws -> R { try await base.withTransaction(block) }
    func observe<T: Storable>(_ type: T.Type, query: QuerySpec?) -> AsyncStream<Result<[T], DatabaseError>> {
        let base = base
        return AsyncStream { continuation in
            Task {
                for await value in await base.observe(type, query: query) { continuation.yield(value) }
                continuation.finish()
            }
        }
    }
    func clearAll(namespace: String) async throws { try await base.clearAll(namespace: namespace) }
}

private struct ScrubCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { "enc:" + String(value.reversed()) }
    func decrypt(_ value: String) -> String {
        value.hasPrefix("enc:") ? String(value.dropFirst(4).reversed()) : value
    }
    func encryptOptional(_ value: String?) -> String? { value.map(encrypt) }
    func decryptOptional(_ value: String?) -> String? { value.map(decrypt) }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
