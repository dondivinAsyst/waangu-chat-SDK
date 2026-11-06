//
//  ConversationSyncPageTests.swift
//  FeatureChatTests
//
//  B49 — la synchronisation des conversations sur le moteur SQLite réel.
//
//  Avant, chaque page passait par `withTransaction`, qui ne commit jamais sur
//  SQLite : la page s'écrivait à moitié puis échouait, et le curseur
//  n'avançait jamais. Les écritures sont maintenant séquentielles : une page
//  s'applique et le curseur avance ; un rejeu ne duplique rien ; une page
//  qui échoue laisse le curseur sur la dernière page réellement appliquée.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class ConversationSyncPageTests: XCTestCase {

    // MARK: - Page appliquée

    func test_pageApplies_andTheCursorAdvances() async throws {
        let ids = [newID(), newID()]
        let harness = await Harness(pages: [.page(ids, cursor: "cursor-1", hasMore: false)])

        let result = try await harness.repository.syncConversations(since: nil, limit: 50)

        XCTAssertEqual(result.createdCount, 2)
        XCTAssertEqual(harness.cursors.getConversationsCursor(), "cursor-1")
        let stored = try await harness.storedConversations(matching: ids)
        XCTAssertEqual(stored.count, 2)
    }

    /// Le rejeu d'une page déjà appliquée met à jour, sans créer de doublon.
    func test_replayingAPage_doesNotDuplicate() async throws {
        let ids = [newID(), newID()]
        let harness = await Harness(pages: [
            .page(ids, cursor: "cursor-1", hasMore: false),
            .page(ids, cursor: "cursor-1", hasMore: false)
        ])

        _ = try await harness.repository.syncConversations(since: nil, limit: 50)
        let replay = try await harness.repository.syncConversations(since: nil, limit: 50)

        XCTAssertEqual(replay.createdCount, 0)
        XCTAssertEqual(replay.updatedCount, 2)
        let stored = try await harness.storedConversations(matching: ids)
        XCTAssertEqual(stored.count, 2)
    }

    /// La page 2 échoue : la page 1 reste écrite, le curseur reste sur elle.
    func test_failingSecondPage_keepsTheCursorOnTheFirst() async throws {
        let first = [newID()]
        let harness = await Harness(pages: [
            .page(first, cursor: "2026-10-09T08:00:00.123Z", hasMore: true),
            .failure
        ])

        do {
            _ = try await harness.repository.syncConversations(since: nil, limit: 50)
            XCTFail("the second page must fail")
        } catch {}

        XCTAssertEqual(harness.cursors.getConversationsCursor(), "2026-10-09T08:00:00.123Z")
        let stored = try await harness.storedConversations(matching: first)
        XCTAssertEqual(stored.count, 1)
    }

    // MARK: - Aperçu illisible (B58)

    /// Un aperçu de message sans `senderId` ne fait plus échouer la page :
    /// toutes les conversations sont synchronisées, celle-là sans aperçu.
    func test_previewWithoutSenderId_doesNotFailThePage() async throws {
        let good = newID()
        let bad = newID()
        let harness = await Harness(pages: [.pageWithBadPreview([good, bad], badPreview: bad)])

        let result = try await harness.repository.syncConversations(since: nil, limit: 50)

        XCTAssertEqual(result.createdCount, 2)
        let stored = try await harness.storedConversations(matching: [good, bad])
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(harness.cursors.getConversationsCursor(), "2026-10-12T08:00:00Z")
    }

    // MARK: - Atomicité de la page (B51)

    /// Une conversation de la page échoue : aucune conversation de cette page
    /// ne reste écrite, et le curseur n'avance pas.
    func test_pageWithOneFailingConversation_writesNothingOfThatPage() async throws {
        let ok = newID()
        let failing = newID()
        let harness = await Harness(
            pages: [.page([ok, failing], cursor: "2026-10-09T08:00:00Z", hasMore: false)],
            failingConversationId: failing
        )

        do {
            _ = try await harness.repository.syncConversations(since: nil, limit: 50)
            XCTFail("the page must fail")
        } catch {}

        let stored = try await harness.storedConversations(matching: [ok, failing])
        XCTAssertEqual(stored.count, 0, "rolled back as a whole")
        XCTAssertNil(harness.cursors.getConversationsCursor())
    }

    // MARK: - Curseurs (B53)

    /// Jeton opaque du serveur (`<ms>|sync|AFTER` en base64) : la pagination
    /// s'arrête au lieu de redemander la page 1 sans fin.
    func test_opaqueNextCursor_stopsPaging_insteadOfRestarting() async throws {
        let harness = await Harness(pages: [
            .page([newID()], cursor: "MTc5MTUzMzgwMTg0NXxzeW5jfEFGVEVS", hasMore: true),
            .page([newID()], cursor: "MTc5MTUzMzgwMTg0NXxzeW5jfEFGVEVS", hasMore: true)
        ])

        _ = try await harness.repository.syncConversations(since: nil, limit: 50)

        XCTAssertEqual(harness.remote.requestedSince.count, 1, "one request, not a restart from page 1")
    }

    /// Un curseur-date (fractions comprises) fait avancer la page suivante.
    func test_dateNextCursor_requestsTheNextPageFromIt() async throws {
        let harness = await Harness(pages: [
            .page([newID()], cursor: "2026-10-09T08:00:00.123456789Z", hasMore: true),
            .page([newID()], cursor: "2026-10-09T09:00:00Z", hasMore: false)
        ])

        _ = try await harness.repository.syncConversations(since: nil, limit: 50)

        XCTAssertEqual(harness.remote.requestedSince.count, 2)
        let second = try XCTUnwrap(harness.remote.requestedSince.last ?? nil)
        XCTAssertEqual(second.timeIntervalSince1970,
                       try XCTUnwrap(ISO8601Timestamp.date(from: "2026-10-09T08:00:00.123456789Z")).timeIntervalSince1970,
                       accuracy: 0.001)
    }

    /// Les messages reprennent au curseur serveur (9 décimales), pas à
    /// l'heure du téléphone enregistrée à côté.
    func test_messageSync_resumesFromTheServerCursor_notTheDeviceClock() async throws {
        let id = newID()
        let harness = await Harness(pages: [.page([id], cursor: "2026-10-09T08:00:00Z", hasMore: false)])
        _ = try await harness.repository.syncConversations(since: nil, limit: 50)
        let stored = try await harness.storedConversations(matching: [id])
        let conversationId = try XCTUnwrap(stored.first?.id)
        let serverCursor = "2026-10-09T08:14:55.347195400Z"
        harness.cursors.saveMessagesCursor(serverCursor, for: conversationId)

        _ = try await harness.repository.syncConversationMessages(conversationId: conversationId, since: nil, limit: 50)

        let since = try XCTUnwrap(harness.remote.requestedMessagesSince.last ?? nil)
        XCTAssertEqual(since.timeIntervalSince1970,
                       try XCTUnwrap(ISO8601Timestamp.date(from: serverCursor)).timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - Alias fusionné

    /// Une conversation fusionnée se synchronise encore sous son id : ses
    /// messages doivent rejoindre la survivante, la seule affichée. Avant, ils
    /// restaient sous l'alias et disparaissaient du fil.
    func test_messagesSyncedForAMergedAlias_landInTheSurvivingConversation() async throws {
        let harness = await Harness(pages: [])
        let survivor = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        var alias = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        alias.mergedIntoId = survivor.id
        try await harness.store.save(survivor)
        try await harness.store.save(alias)
        let messageId = "m-\(UUID().uuidString.lowercased())"
        harness.remote.messageItems = [[
            "timelineId": "t-1", "type": "MESSAGE", "sortKey": 1,
            "occurredAt": "2026-10-09T08:09:47.000Z", "itemKey": "k-1",
            "message": ["codeMessage": messageId, "senderId": "peer", "content": "{\"text\":\"bonjour\"}",
                        "typeMessage": "TEXT", "sentAt": "2026-10-09T08:09:47.000Z"]
        ]]

        _ = try await harness.repository.syncConversationMessages(conversationId: alias.id, since: nil, limit: 50)

        let fetched = try await harness.store.fetchOne(MessageModel.self, id: messageId)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.conversationId, survivor.id)
        XCTAssertEqual(harness.remote.requestedMessagesConversationIds.last, alias.id,
                       "the server is still asked under the id it knows")
    }

    // MARK: - Horodatage (B52)

    /// Le backend envoie des fractions de seconde : la conversation garde
    /// l'heure de sa dernière activité, pas celle de la synchronisation.
    func test_lastActivityWithMilliseconds_isKept_notReplacedBySyncTime() async throws {
        let id = newID()
        let activity = "2026-10-08T08:51:57.123Z"
        let harness = await Harness(pages: [.pageAt([id], activity: activity, cursor: "cursor-1", hasMore: false)])

        _ = try await harness.repository.syncConversations(since: nil, limit: 50)

        let stored = try await harness.storedConversations(matching: [id])
        let expected = try XCTUnwrap(ISO8601Timestamp.date(from: activity))
        let lastMessageAt = try XCTUnwrap(stored.first?.lastMessageAt)
        XCTAssertEqual(lastMessageAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Outils

    private func newID() -> String { "grp-\(UUID().uuidString.lowercased())" }
}

// MARK: - Harnais

private enum ScriptedPage {
    case page([String], cursor: String, hasMore: Bool)
    case pageAt([String], activity: String, cursor: String, hasMore: Bool)
    /// La conversation `badPreview` porte un aperçu de message sans `senderId`.
    case pageWithBadPreview([String], badPreview: String)
    case failure
}

private struct ScriptedFailure: Error {}

private final class Harness: @unchecked Sendable {
    let repository: DiscussionRepository
    let cursors: SyncCursorStore
    let store: any SearchableDatabaseProtocol
    let remote: ScriptedConversationSync

    init(pages: [ScriptedPage], failingConversationId: String? = nil) async {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        self.store = store
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        cursors = SyncCursorStore(userDefaults: UserDefaults(suiteName: "sync-page-\(UUID().uuidString)")!)
        let crypto = PassthroughFieldCrypto()
        remote = ScriptedConversationSync(pages: pages)
        repository = DiscussionRepository(
            localDataSource: DiscussionDataSourceFactory.create(store: store, fieldCrypto: crypto),
            remoteConversationSyncDataSource: remote,
            database: failingConversationId.map { FailingSaveDatabase(base: store, failingId: $0) } ?? store,
            syncCursorStore: cursors,
            fieldCrypto: crypto,
            chatActionsDataSource: ChatActionsDataSourceFactory.shared.makeLocalDataSource(store: store),
            deviceInfoProvider: FixedDeviceInfo()
        )
    }

    /// Conversations stockées sous l'un des identifiants serveur donnés.
    func storedConversations(matching ids: [String]) async throws -> [ConversationModel] {
        let all = try await store.fetch(ConversationModel.self, query: nil)
        return all.filter { ids.contains($0.id) || ids.contains($0.serverId ?? "") || ids.contains($0.groupId ?? "") }
    }
}

private final class ScriptedConversationSync: RemoteConversationSyncDataSourceProtocol, @unchecked Sendable {
    private var pages: [ScriptedPage]
    private let lock = NSLock()
    private(set) var requestedSince: [Date?] = []
    private(set) var requestedMessagesSince: [Date?] = []
    private(set) var requestedMessagesConversationIds: [String] = []
    var messageItems: [[String: Any]] = []

    init(pages: [ScriptedPage]) { self.pages = pages }

    func syncConversations(since: Date?, limit: Int) async throws -> ConversationSyncResponseDTO {
        let next: ScriptedPage? = lock.withLock {
            requestedSince.append(since)
            return pages.isEmpty ? nil : pages.removeFirst()
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let ids: [String], cursor: String, hasMore: Bool, activity: String
        var badPreview: String?
        switch next {
        case .page(let i, let c, let h)?: (ids, cursor, hasMore, activity) = (i, c, h, now)
        case .pageAt(let i, let a, let c, let h)?: (ids, cursor, hasMore, activity) = (i, c, h, a)
        case .pageWithBadPreview(let i, let bad)?:
            (ids, cursor, hasMore, activity) = (i, "2026-10-12T08:00:00Z", false, now)
            badPreview = bad
        default: throw ScriptedFailure()
        }
        let body: [String: Any] = [
            "success": true,
            "hasMore": hasMore,
            "data": [
                "serverTime": now,
                "nextSinceCursor": cursor,
                "changedConversations": ids.map { id -> [String: Any] in
                    var item: [String: Any] = [
                        "conversationId": id, "conversationType": "GROUP", "displayTitle": "Groupe \(id.suffix(4))",
                        "lastActivityAt": activity, "userState": ["unreadCount": 0], "changeType": "CREATED"]
                    if id == badPreview {
                        // Forme observée le 2026-10-12 : l'aperçu sans `senderId`.
                        item["messages"] = ["codeMessage": "m-\(id.suffix(6))", "content": "{}", "typeMessage": "TEXT"]
                    }
                    return item
                }
            ]
        ]
        return try JSONDecoder().decode(ConversationSyncResponseDTO.self,
                                        from: JSONSerialization.data(withJSONObject: body))
    }

    /// Une page de messages vide : seul le `since` demandé intéresse les tests.
    func syncConversationMessages(conversationId: String, since: Date?, limit: Int) async throws -> MessageSyncResponseDTO {
        let items: [[String: Any]] = lock.withLock {
            requestedMessagesSince.append(since)
            requestedMessagesConversationIds.append(conversationId)
            return messageItems
        }
        let body: [String: Any] = ["success": true, "data": ["items": items, "count": items.count]]
        return try JSONDecoder().decode(MessageSyncResponseDTO.self, from: JSONSerialization.data(withJSONObject: body))
    }
}

private struct FixedDeviceInfo: DeviceInfoProvidingProtocol {
    func captureSnapshot() -> DeviceInfoSnapshot {
        DeviceInfoSnapshot(processorCount: 6, physicalMemoryMB: 8_192, modelIdentifier: "iPhone17,1", systemVersion: "26.1")
    }
    func captureDeviceContext() -> DeviceContext {
        DeviceContext(deviceId: "device-test", deviceModel: "iPhone", brandName: "Apple", manufacturer: "Apple",
                      osVersion: "26.1", appVersion: "1.0", buildNumber: "1", platformOS: "iOS")
    }
}

private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}

/// Le store réel, sauf l'écriture d'une conversation choisie, qui échoue.
private actor FailingSaveDatabase: DatabaseRepositoryProtocol {
    let base: any SearchableDatabaseProtocol
    let failingId: String
    struct Refused: Error {}

    init(base: any SearchableDatabaseProtocol, failingId: String) {
        self.base = base
        self.failingId = failingId
    }

    func save<T: Storable>(_ entity: T) async throws {
        if let conversation = entity as? ConversationModel,
           conversation.id == failingId || conversation.serverId == failingId || conversation.groupId == failingId {
            throw Refused()
        }
        try await base.save(entity)
    }
    func saveAll<T: Storable>(_ entities: [T]) async throws { for entity in entities { try await save(entity) } }
    func fetch<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> [T] { try await base.fetch(type, query: query) }
    func fetchOne<T: Storable>(_ type: T.Type, id: T.ID) async throws -> T? { try await base.fetchOne(type, id: id) }
    func count<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> Int { try await base.count(type, query: query) }
    func delete<T: Storable>(_ type: T.Type, id: T.ID) async throws { try await base.delete(type, id: id) }
    func deleteAll<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws { try await base.deleteAll(type, query: query) }
    func withTransaction<R: Sendable>(_ block: @Sendable () async throws -> R) async throws -> R {
        try await base.withTransaction(block)
    }
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
