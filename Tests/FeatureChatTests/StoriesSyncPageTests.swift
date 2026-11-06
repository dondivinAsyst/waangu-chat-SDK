//
//  StoriesSyncPageTests.swift
//  FeatureChatTests
//
//  B49 — la synchronisation des stories sur le moteur SQLite réel.
//
//  Même correction que pour les conversations : les pages ne passent plus par
//  `withTransaction`, qui ne commit jamais sur SQLite. Une page s'applique et le
//  curseur avance ; un rejeu ne duplique rien ; une page qui échoue laisse le
//  curseur sur la dernière page réellement appliquée.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class StoriesSyncPageTests: XCTestCase {

    func test_pageApplies_andTheCursorAdvances() async throws {
        let ids = [newID(), newID()]
        let harness = await StoriesHarness(pages: [.page(ids, cursor: "2026-10-09T08:00:00Z", hasMore: false)])

        let synced = try await harness.repository.syncStories(limit: 50)

        XCTAssertEqual(synced, 2)
        XCTAssertEqual(harness.cursors.getStoriesCursor(), "2026-10-09T08:00:00Z")
        let stored = try await harness.storedStories(ids)
        XCTAssertEqual(stored.count, 2)
    }

    /// Le rejeu réécrit les mêmes statuts par leur id : aucun doublon.
    func test_replayingAPage_doesNotDuplicate() async throws {
        let ids = [newID()]
        let harness = await StoriesHarness(pages: [
            .page(ids, cursor: "2026-10-09T08:00:00Z", hasMore: false),
            .page(ids, cursor: "2026-10-09T08:00:00Z", hasMore: false)
        ])

        _ = try await harness.repository.syncStories(limit: 50)
        _ = try await harness.repository.syncStories(limit: 50)

        let all = try await harness.store.fetch(StatusModel.self, query: nil)
        XCTAssertEqual(all.filter { ids.contains($0.id) }.count, 1)
    }

    /// La page 2 échoue : la page 1 reste écrite, le curseur reste sur elle.
    func test_failingSecondPage_keepsTheCursorOnTheFirst() async throws {
        let first = [newID()]
        let harness = await StoriesHarness(pages: [
            .page(first, cursor: "2026-10-09T08:00:00Z", hasMore: true),
            .failure
        ])

        do {
            _ = try await harness.repository.syncStories(limit: 50)
            XCTFail("the second page must fail")
        } catch {}

        XCTAssertEqual(harness.cursors.getStoriesCursor(), "2026-10-09T08:00:00Z")
        let stored = try await harness.storedStories(first)
        XCTAssertEqual(stored.count, 1)
    }

    /// B53 — jeton opaque : la pagination s'arrête au lieu de repartir du début.
    func test_opaqueNextCursor_stopsPaging_insteadOfRestarting() async throws {
        let harness = await StoriesHarness(pages: [
            .page([newID()], cursor: "MTc5MTUzMzM0NTEwMHxzeW5jfEFGVEVS", hasMore: true),
            .page([newID()], cursor: "MTc5MTUzMzM0NTEwMHxzeW5jfEFGVEVS", hasMore: true)
        ])

        _ = try await harness.repository.syncStories(limit: 50)

        XCTAssertEqual(harness.remote.requestCount, 1, "one request, not a restart from page 1")
    }

    private func newID() -> String { "story-\(UUID().uuidString.lowercased())" }
}

// MARK: - Harnais

private enum ScriptedStoriesPage {
    case page([String], cursor: String, hasMore: Bool)
    case failure
}

private struct ScriptedStoriesFailure: Error {}

private final class StoriesHarness: @unchecked Sendable {
    let repository: StatusRepository
    let cursors: SyncCursorStore
    let store: any SearchableDatabaseProtocol
    let remote: ScriptedStoriesSync

    init(pages: [ScriptedStoriesPage]) async {
        store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        cursors = SyncCursorStore(userDefaults: UserDefaults(suiteName: "stories-page-\(UUID().uuidString)")!)
        remote = ScriptedStoriesSync(pages: pages)
        repository = StatusRepository(
            localDataSource: StatusDataSourceFactory.create(store: store, fieldCrypto: PassthroughFieldCrypto()),
            httpDataSource: remote,
            mapper: StatusMappers(),
            eventBus: InMemoryEventBus(),
            syncCursorStore: cursors,
            database: store
        )
    }

    func storedStories(_ ids: [String]) async throws -> [StatusModel] {
        try await store.fetch(StatusModel.self, query: nil).filter { ids.contains($0.id) }
    }
}

private final class ScriptedStoriesSync: HTTPStatusDataSourceProtocol, @unchecked Sendable {
    private var pages: [ScriptedStoriesPage]
    private let lock = NSLock()

    private(set) var requestCount = 0

    init(pages: [ScriptedStoriesPage]) { self.pages = pages }

    func syncStories(since: Date?, limit: Int) async throws -> StoriesSyncResponseDTO {
        let next: ScriptedStoriesPage? = lock.withLock {
            requestCount += 1
            return pages.isEmpty ? nil : pages.removeFirst()
        }
        guard case .page(let ids, let cursor, let hasMore)? = next else { throw ScriptedStoriesFailure() }
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = [
            "success": true,
            "data": [
                "serverTime": now,
                "nextSinceCursor": cursor,
                "hasMore": hasMore,
                "changedStories": [[
                    "creatorId": "creator-1",
                    "creatorDisplayName": "Aline",
                    "stories": ids.map { ["storyId": $0, "creatorId": "creator-1", "storyType": "text",
                                          "content": "bonjour", "createdAt": now] }
                ]]
            ]
        ]
        return try JSONDecoder().decode(StoriesSyncResponseDTO.self, from: JSONSerialization.data(withJSONObject: body))
    }

    func getContactStatus() async throws -> APIResponse { throw ScriptedStoriesFailure() }
    func onPostStatus(_ request: CreateStatusRequest) async throws -> APIResponse { throw ScriptedStoriesFailure() }
    func deleteStatus(_ request: DeleteStatusRequest) async throws -> APIResponse { throw ScriptedStoriesFailure() }
}

private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
