//
//  FeatureSyncEngineSessionTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, F-09 / F-11 — le moteur de synchro générique (StorageKit) ne
//  s'applique plus au compte suivant, et une page qui n'arrive pas ne clôt pas la synchro.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class FeatureSyncEngineSessionTests: XCTestCase {

    // MARK: - F-09 : changement de compte pendant une page

    func test_pageArrivingAfterAccountSwitch_appliesNothing_andLeavesTheStateAlone() async throws {
        let h = try await Harness()
        h.delegate.onFetch = { h.session.set("someone-else") } // the switch lands while the page is in flight
        h.delegate.pages = [SyncPage(events: ["e1", "e2"], nextCursor: "c2", hasMore: true)]

        await h.engine.pullMissedEvents()

        XCTAssertEqual(h.delegate.processed, [], "Late page must not be applied to the next account")
        let state = try await h.state()
        XCTAssertNil(state?.currentCursor, "The previous account's cursor must not be written")
        XCTAssertNil(state?.lastSyncTimestamp)
    }

    func test_unchangedAccount_appliesThePage_andClosesTheSync() async throws {
        let h = try await Harness()
        h.delegate.pages = [SyncPage(events: ["e1", "e2"], nextCursor: nil, hasMore: false)]

        await h.engine.pullMissedEvents()

        XCTAssertEqual(h.delegate.processed, ["e1", "e2"])
        let state = try await h.state()
        XCTAssertNotNil(state?.lastSyncTimestamp)
        XCTAssertEqual(state?.isSyncing, false)
    }

    // MARK: - F-11 : une page manquée ne vaut pas synchro complète

    func test_failedFirstPage_doesNotRecordAFullSync() async throws {
        let h = try await Harness()
        h.delegate.pages = [] // fetchPage throws

        await h.engine.pullMissedEvents()

        let state = try await h.state()
        XCTAssertNil(state?.lastSyncTimestamp, "A sync that never received a page must not move the watermark")
    }

    // MARK: - N-02 : écriture refusée

    /// Un événement dont l'écriture échoue arrête le pull : le curseur et le repère de synchro
    /// ne bougent pas, et les événements suivants de la page ne sont pas appliqués.
    func test_failedEvent_stopsThePull_andKeepsTheCursorBehind() async throws {
        let h = try await Harness()
        h.delegate.failing = ["bad"]
        h.delegate.pages = [SyncPage(events: ["ok-1", "bad", "after"], nextCursor: "c2", hasMore: true)]

        await h.engine.pullMissedEvents()

        XCTAssertEqual(h.delegate.processed, ["ok-1"], "Nothing after the failed event may be applied")
        let state = try await h.state()
        XCTAssertNil(state?.currentCursor, "The cursor must not pass an event that was never stored")
        XCTAssertNil(state?.lastSyncTimestamp, "An incomplete pull must not close the sync")
    }

    func test_pageWithoutFailure_stillAdvancesTheCursor() async throws {
        let h = try await Harness()
        h.delegate.pages = [SyncPage(events: ["a", "b"], nextCursor: "c2", hasMore: true),
                            SyncPage(events: ["c"], nextCursor: nil, hasMore: false)]

        await h.engine.pullMissedEvents()

        XCTAssertEqual(h.delegate.processed, ["a", "b", "c"])
        let state = try await h.state()
        XCTAssertNotNil(state?.lastSyncTimestamp)
    }

    // MARK: - Realtime

    func test_realtimeEvents_stopBeingAppliedOnceTheAccountChanges() async throws {
        let h = try await Harness()
        h.delegate.pages = [SyncPage(events: [], nextCursor: nil, hasMore: false)]
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        h.delegate.live = RealtimeSync(stream: stream, token: StubToken())

        await h.engine.pullMissedEvents()
        continuation.yield("live-1")
        try await waitUntil { h.delegate.processed == ["live-1"] }
        h.session.set("someone-else")
        continuation.yield("live-2")
        continuation.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(h.delegate.processed, ["live-1"])
    }

    /// N-02 : un événement live dont l'écriture est refusée n'est pas tenu pour appliqué ;
    /// un pull le relit et, la base répondant de nouveau, l'applique.
    func test_refusedLiveEvent_isReReadByAPull_andThenApplied() async throws {
        let h = try await Harness()
        h.delegate.pages = [SyncPage(events: [], nextCursor: nil, hasMore: false)]
        h.delegate.failOnce = ["live-bad"]
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        h.delegate.live = RealtimeSync(stream: stream, token: StubToken())
        await h.engine.pullMissedEvents()

        h.delegate.pages = [SyncPage(events: ["live-bad"], nextCursor: nil, hasMore: false)]
        continuation.yield("live-bad")
        try await waitUntil { h.delegate.processed == ["live-bad"] }
        continuation.finish()

        let state = try await h.state()
        XCTAssertNil(state?.blockedAttempts, "The re-read applied it, nothing stays blocked")
    }

    /// Si l'écriture reste refusée, le pull de reprise compte l'échec (dégradation au seuil)
    /// au lieu de laisser l'événement disparaître sans trace.
    func test_refusedLiveEvent_thatStaysRefused_isCountedNotLost() async throws {
        let h = try await Harness()
        h.delegate.pages = [SyncPage(events: [], nextCursor: nil, hasMore: false)]
        h.delegate.failing = ["live-bad"]
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        h.delegate.live = RealtimeSync(stream: stream, token: StubToken())
        await h.engine.pullMissedEvents()

        h.delegate.pages = [SyncPage(events: ["live-bad"], nextCursor: nil, hasMore: false)]
        continuation.yield("live-bad")
        var counted = false
        for _ in 0..<100 where !counted {
            counted = (try await h.state())?.blockedAttempts == 1
            if !counted { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        continuation.finish()

        XCTAssertTrue(counted)
        XCTAssertTrue(h.delegate.processed.isEmpty)
    }

    /// `liveUpdates: false` : le pull se fait, mais aucun flux live n'est ouvert, donc un
    /// événement live n'est pas appliqué une seconde fois à côté de celui de la feature.
    func test_withoutLiveUpdates_theStreamIsNeverConsumed() async throws {
        let h = try await Harness(liveUpdates: false)
        h.delegate.pages = [SyncPage(events: ["pulled"], nextCursor: nil, hasMore: false)]
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        h.delegate.live = RealtimeSync(stream: stream, token: StubToken())

        await h.engine.pullMissedEvents()
        continuation.yield("live-1")
        continuation.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(h.delegate.processed, ["pulled"], "Only the pull applies events")
    }

    // MARK: - Outils

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), "Timed out")
    }

    // MARK: - Réessai borné

    /// Le même événement refusé à chaque passage : le compteur monte, la synchro devient
    /// dégradée au seuil, et l'événement n'est jamais sauté ni le curseur avancé.
    func test_sameEventFailingEveryPass_isCounted_thenFlaggedDegraded_neverSkipped() async throws {
        let h = try await Harness()
        h.delegate.failing = ["bad"]

        let before = await h.engine.isDegraded()
        XCTAssertFalse(before)
        for pass in 1...SyncState.maxBlockedAttempts {
            h.delegate.pages = [SyncPage(events: ["bad", "after"], nextCursor: nil, hasMore: false)]
            await h.engine.pullMissedEvents()
            let state = try await h.state()
            XCTAssertEqual(state?.blockedAttempts, pass)
            XCTAssertEqual(state?.isDegraded, pass >= SyncState.maxBlockedAttempts)
        }

        let degraded = await h.engine.isDegraded()
        XCTAssertTrue(degraded, "The engine reports the degraded state the host can read")
        XCTAssertTrue(h.delegate.processed.isEmpty, "A refused event is neither applied nor skipped")
        let state = try await h.state()
        XCTAssertNil(state?.lastSyncTimestamp)
        XCTAssertEqual(state?.blockedReason, "scripted")
    }

    /// Dès que l'événement passe, le compteur et l'état dégradé disparaissent.
    func test_blockedEventThatFinallyApplies_clearsTheCounter() async throws {
        let h = try await Harness()
        h.delegate.failing = ["bad"]
        h.delegate.pages = [SyncPage(events: ["bad"], nextCursor: nil, hasMore: false)]
        await h.engine.pullMissedEvents()
        let blocked = try await h.state()
        XCTAssertEqual(blocked?.blockedAttempts, 1)

        h.delegate.failing = []
        h.delegate.pages = [SyncPage(events: ["bad"], nextCursor: nil, hasMore: false)]
        await h.engine.pullMissedEvents()

        let state = try await h.state()
        XCTAssertEqual(h.delegate.processed, ["bad"])
        XCTAssertNil(state?.blockedAttempts)
        XCTAssertNil(state?.blockedEventKey)
        XCTAssertEqual(state?.isDegraded, false)
        XCTAssertNotNil(state?.lastSyncTimestamp)
    }

    /// Un autre événement qui bute repart à 1 : on ne compte pas d'un événement à l'autre.
    func test_aDifferentFailingEvent_restartsTheCount() async throws {
        let h = try await Harness()
        h.delegate.failing = ["bad", "worse"]
        h.delegate.pages = [SyncPage(events: ["bad"], nextCursor: nil, hasMore: false)]
        await h.engine.pullMissedEvents()
        h.delegate.pages = [SyncPage(events: ["ok", "worse"], nextCursor: nil, hasMore: false)]
        await h.engine.pullMissedEvents()

        let state = try await h.state()
        XCTAssertEqual(state?.blockedAttempts, 1)
    }

    private struct Harness {
        let session = SessionBox("me")
        let delegate: ScriptedDelegate
        let store: any DatabaseRepositoryProtocol
        let engine: FeatureSyncEngine<ScriptedDelegate>

        init(liveUpdates: Bool = true) async throws {
            let store = DatabaseAssembly.makeSearchable(
                config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
            await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
            let delegate = ScriptedDelegate()
            let session = self.session
            self.store = store
            self.delegate = delegate
            self.engine = FeatureSyncEngine(
                delegate: delegate,
                outbox: StubOutbox(),
                apiClient: UnusedAPIClient(),
                database: store,
                realtime: RecordingRealtimeClient(),
                syncPriority: .high,
                pullConfig: SyncEngineConfiguration(pullPageSize: 10, interPageDelay: 0),
                currentOwner: { session.value },
                liveUpdates: liveUpdates
            )
        }

        func state() async throws -> SyncState? {
            try await store.fetchOne(SyncState.self, id: delegate.featureName)
        }
    }
}

// MARK: - Doubles

private final class SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String
    init(_ initial: String) { current = initial }
    var value: String { lock.lock(); defer { lock.unlock() }; return current }
    func set(_ new: String) { lock.lock(); current = new; lock.unlock() }
}

private final class ScriptedDelegate: SyncDelegate, @unchecked Sendable {
    typealias SyncEvent = String
    struct NoPage: Error {}

    // Unique per test: SyncState rows persist between runs.
    let featureName = "engine-test-\(UUID().uuidString)"
    private let lock = NSLock()
    private var _processed: [String] = []
    private var _pages: [SyncPage<String>] = []
    var onFetch: (() -> Void)?
    /// Events whose write is refused (applyEvent reports .failed and stores nothing).
    var failing: Set<String> = []
    /// Events refused the first time only (a write that fails once, then works).
    var failOnce: Set<String> = []
    var live: RealtimeSync<String>?

    var processed: [String] { lock.withLock { _processed } }
    var pages: [SyncPage<String>] {
        get { lock.withLock { _pages } }
        set { lock.withLock { _pages = newValue } }
    }

    func fetchPage(since: Date?, cursor: String?, limit: Int, apiClient: any APIClientProtocol) async throws -> SyncPage<String> {
        onFetch?()
        guard let page = lock.withLock({ _pages.isEmpty ? nil : _pages.removeFirst() }) else { throw NoPage() }
        return page
    }

    func processEvent(_ event: String, database: any DatabaseRepositoryProtocol) async {
        lock.withLock { _processed.append(event) }
    }

    func applyEvent(_ event: String, database: any DatabaseRepositoryProtocol) async -> SyncApplyOutcome {
        if failing.contains(event) { return .failed(reason: "scripted") }
        if lock.withLock({ failOnce.remove(event) }) != nil { return .failed(reason: "scripted once") }
        await processEvent(event, database: database)
        return .applied
    }

    func realtimeSubscription(realtime: any RealtimeClientProtocol) async throws -> RealtimeSync<String>? { live }
}

private struct StubOutbox: OutboxFlushing {
    typealias Item = ChatOutboxItem
    func enqueue(_ item: ChatOutboxItem) async throws {}
    func flush() async -> [OutboxFlushResult] { [] }
    var pendingCount: Int { get async { 0 } }
}

private final class StubToken: RealtimeSubscriptionToken, @unchecked Sendable {
    let id = UUID()
    var topic: RealtimeTopic { ChatMQTTTopics.userInbox(userId: "me") }
    var feature: String? { "chat" }
    var isActive: Bool { get async { true } }
    func cancel() async {}
}

private final class UnusedAPIClient: APIClientProtocol, @unchecked Sendable {
    struct Unused: Error {}
    var isConnected: Bool { get async { true } }
    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T { throw Unused() }
    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}
