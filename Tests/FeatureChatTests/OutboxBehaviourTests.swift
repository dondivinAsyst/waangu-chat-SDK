//
//  OutboxBehaviourTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, messaging / offline — `DatabaseOutbox` on a real database, with the
//  chat's own item type: one queued action per idempotency key, retries that run out, a
//  permanent refusal that does not retry, an item stuck mid-send that is picked up again,
//  settling by the server's acknowledgement, and no two flushes at once. Unit level: the
//  network is a closure.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class OutboxBehaviourTests: XCTestCase {

    // MARK: - Fixtures

    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func config(maxRetries: Int = 3, batchSize: Int = 30, stuckTimeout: TimeInterval = 120) -> OutboxConfiguration {
        OutboxConfiguration(batchSize: batchSize, maxRetries: maxRetries, stuckTimeout: stuckTimeout,
                            syncedRetention: 86_400, interBatchDelay: 0)
    }

    /// Rows left by other runs share the file: items are told apart by a per-test prefix, and
    /// the flush closure clears the ones that are not ours so they cannot interfere.
    private struct Harness {
        let prefix = "t-\(UUID().uuidString)"
        let store: any DatabaseRepositoryProtocol
        let outbox: DatabaseOutbox<ChatOutboxItem>
        let seen: Seen

        init(store: any DatabaseRepositoryProtocol, config: OutboxConfiguration,
             decide: @escaping @Sendable (ChatOutboxItem) async throws -> OutboxFlushResult?) {
            self.store = store
            let seen = Seen()
            self.seen = seen
            let prefix = self.prefix
            self.outbox = DatabaseOutbox<ChatOutboxItem>(database: store, config: config) { batch in
                var results: [OutboxFlushResult] = []
                for item in batch {
                    if item.idempotencyKey.hasPrefix(prefix) {
                        await seen.record(item.idempotencyKey)
                        if let result = try await decide(item) { results.append(result) }
                    } else {
                        results.append(OutboxFlushResult(localId: item.id, success: true))
                    }
                }
                return results
            }
        }

        func item(_ name: String, createdAt: Date = Date(), status: OutboxSyncStatus = .pending) -> ChatOutboxItem {
            ChatOutboxItem(actionType: .sendMessage, payload: Data(), idempotencyKey: "\(prefix):\(name)",
                           conversationId: "c", createdAt: createdAt, syncStatus: status)
        }

        func stored(_ item: ChatOutboxItem) async throws -> ChatOutboxItem? {
            try await store.fetchOne(ChatOutboxItem.self, id: item.id)
        }

        func rows(named name: String) async throws -> [ChatOutboxItem] {
            try await store.fetch(ChatOutboxItem.self, query: QuerySpec(
                filter: FilterSpec("idempotency_key = %@", .string("\(prefix):\(name)"))))
        }
    }

    private actor Seen {
        private(set) var keys: [String] = []
        func record(_ key: String) { keys.append(key) }
    }

    private func harness(maxRetries: Int = 3, batchSize: Int = 30, stuckTimeout: TimeInterval = 120,
                         decide: @escaping @Sendable (ChatOutboxItem) async throws -> OutboxFlushResult?
                            = { OutboxFlushResult(localId: $0.id, success: true) }) async -> Harness {
        Harness(store: await makeStore(),
                config: config(maxRetries: maxRetries, batchSize: batchSize, stuckTimeout: stuckTimeout),
                decide: decide)
    }

    // MARK: - Enqueue

    func test_enqueue_sameKeyWhilePending_isIgnored() async throws {
        let h = await harness()

        try await h.outbox.enqueue(h.item("a"))
        try await h.outbox.enqueue(h.item("a"))

        let rows = try await h.rows(named: "a")
        XCTAssertEqual(rows.count, 1, "One queued action per idempotency key")
        XCTAssertEqual(rows.first?.syncStatus, .pending)
    }

    func test_enqueue_sameKeyAfterAFailure_queuesAFreshAttempt() async throws {
        let h = await harness()
        let first = h.item("a", status: .failed)
        try await h.store.save(first)

        try await h.outbox.enqueue(h.item("a"))

        let rows = try await h.rows(named: "a")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.filter { $0.syncStatus == .pending }.count, 1)
    }

    // MARK: - Flush

    func test_flush_success_marksTheItemSynced() async throws {
        let h = await harness()
        let item = h.item("a")
        try await h.outbox.enqueue(item)

        await h.outbox.flush()

        let stored = try await h.stored(item)
        XCTAssertEqual(stored?.syncStatus, .synced)
    }

    func test_flush_retryableFailure_keepsItPending_andCountsTheAttempt() async throws {
        let h = await harness(maxRetries: 3) { OutboxFlushResult(localId: $0.id, success: false, error: "offline", retryable: true) }
        let item = h.item("a")
        try await h.outbox.enqueue(item)

        await h.outbox.flush()

        let stored = try await h.stored(item)
        XCTAssertEqual(stored?.syncStatus, .pending)
        XCTAssertEqual(stored?.retryCount, 1)
        XCTAssertEqual(stored?.lastError, "offline")
    }

    /// A short outage must not burn the item's retries: one flush attempts it once, the next
    /// flush (reconnect, foreground) attempts it again.
    func test_flush_triesARetryableItemOnlyOncePerFlush() async throws {
        let h = await harness(maxRetries: 5) { OutboxFlushResult(localId: $0.id, success: false, error: "offline", retryable: true) }
        try await h.outbox.enqueue(h.item("a"))

        await h.outbox.flush()

        let attempts = await h.seen.keys.count
        XCTAssertEqual(attempts, 1)
    }

    func test_flush_retriesRunOut_andTheItemFails() async throws {
        let h = await harness(maxRetries: 2) { OutboxFlushResult(localId: $0.id, success: false, error: "offline", retryable: true) }
        let item = h.item("a")
        try await h.outbox.enqueue(item)

        await h.outbox.flush()
        await h.outbox.flush()
        await h.outbox.flush()   // nothing left to send: the item is not picked up again

        let stored = try await h.stored(item)
        XCTAssertEqual(stored?.syncStatus, .failed)
        XCTAssertEqual(stored?.retryCount, 2)
        let attempts = await h.seen.keys.count
        XCTAssertEqual(attempts, 2, "A failed item is not sent again")
    }

    func test_flush_permanentRefusal_failsAtOnce_withoutRetrying() async throws {
        let h = await harness { OutboxFlushResult(localId: $0.id, success: false, error: "bad", errorCode: "INVALID_PAYLOAD") }
        let item = h.item("a")
        try await h.outbox.enqueue(item)

        await h.outbox.flush()

        let stored = try await h.stored(item)
        XCTAssertEqual(stored?.syncStatus, .failed)
        XCTAssertEqual(stored?.retryCount, 0)
    }

    func test_flush_whenTheSendThrows_countsAnAttemptOnEveryItemOfTheBatch() async throws {
        struct Offline: Error {}
        let h = await harness { _ in throw Offline() }
        let first = h.item("a"), second = h.item("b")
        try await h.outbox.enqueue(first)
        try await h.outbox.enqueue(second)

        await h.outbox.flush()

        let a = try await h.stored(first), b = try await h.stored(second)
        XCTAssertEqual(a?.retryCount, 1)
        XCTAssertEqual(b?.retryCount, 1)
        XCTAssertEqual(a?.syncStatus, .pending)
    }

    func test_flush_sendsTheOldestFirst() async throws {
        let h = await harness(batchSize: 1)
        let now = Date()
        try await h.outbox.enqueue(h.item("newest", createdAt: now))
        try await h.outbox.enqueue(h.item("oldest", createdAt: now.addingTimeInterval(-300)))
        try await h.outbox.enqueue(h.item("middle", createdAt: now.addingTimeInterval(-100)))

        await h.outbox.flush()

        let order = await h.seen.keys.map { $0.replacingOccurrences(of: "\(h.prefix):", with: "") }
        XCTAssertEqual(order, ["oldest", "middle", "newest"])
    }

    func test_flush_picksUpAnItemStuckMidSend_afterTheTimeout() async throws {
        let h = await harness(stuckTimeout: 60)
        let stuck = h.item("a", createdAt: Date().addingTimeInterval(-600), status: .syncing)
        try await h.store.save(stuck)

        await h.outbox.flush()

        let stored = try await h.stored(stuck)
        XCTAssertEqual(stored?.syncStatus, .synced, "A crash between send and answer must not lose the action")
    }

    func test_flush_leavesARecentItemInFlightAlone() async throws {
        let h = await harness(stuckTimeout: 3_600)
        let inFlight = h.item("a", createdAt: Date(), status: .syncing)
        try await h.store.save(inFlight)

        await h.outbox.flush()

        let stored = try await h.stored(inFlight)
        XCTAssertEqual(stored?.syncStatus, .syncing)
    }

    func test_flush_whileAnotherFlushRuns_doesNothing() async throws {
        let gate = Gate()
        let h = await harness { item in
            await gate.wait()
            return OutboxFlushResult(localId: item.id, success: true)
        }
        try await h.outbox.enqueue(h.item("a"))

        let first = Task { await h.outbox.flush() }
        while await h.seen.keys.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        let second = await h.outbox.flush()
        await gate.open()
        _ = await first.value

        XCTAssertTrue(second.isEmpty, "Two flushes at once would send the same action twice")
        let attempts = await h.seen.keys.count
        XCTAssertEqual(attempts, 1)
    }

    // MARK: - Settling and replay

    func test_settle_acknowledged_clearsTheMatchingKey_andReportsHowMany() async throws {
        let h = await harness()
        let item = h.item("m1")
        let other = h.item("m2")
        try await h.outbox.enqueue(item)
        try await h.outbox.enqueue(other)

        let count = await h.outbox.settle(key: "\(h.prefix):m1", success: true)

        XCTAssertEqual(count, 1)
        let settled = try await h.stored(item), untouched = try await h.stored(other)
        XCTAssertEqual(settled?.syncStatus, .synced)
        XCTAssertEqual(untouched?.syncStatus, .pending)
    }

    func test_settle_rejected_marksItFailed_withTheReason() async throws {
        let h = await harness()
        let item = h.item("m1")
        try await h.outbox.enqueue(item)

        await h.outbox.settle(key: "\(h.prefix):m1", success: false, error: "blocked")

        let stored = try await h.stored(item)
        XCTAssertEqual(stored?.syncStatus, .failed)
        XCTAssertEqual(stored?.lastError, "blocked")
    }

    func test_settle_anAcknowledgementForSomethingNeverQueued_settlesNothing() async {
        let h = await harness()

        let count = await h.outbox.settle(key: "\(h.prefix):never", success: true)

        XCTAssertEqual(count, 0)
    }

    func test_pending_olderThan_listsOnlyOldPendingItems_oldestFirst() async throws {
        let h = await harness()
        let now = Date()
        let old = h.item("old", createdAt: now.addingTimeInterval(-500))
        let older = h.item("older", createdAt: now.addingTimeInterval(-900))
        let fresh = h.item("fresh", createdAt: now)
        let doneButOld = h.item("done", createdAt: now.addingTimeInterval(-900), status: .synced)
        for item in [old, older, fresh, doneButOld] { try await h.store.save(item) }

        let pending = await h.outbox.pending(olderThan: 60).filter { $0.idempotencyKey.hasPrefix(h.prefix) }

        XCTAssertEqual(pending.map(\.id), [older.id, old.id])
    }

    func test_noteAttempt_countsAReplay_andFailsTheItemWhenAttemptsRunOut() async throws {
        let h = await harness(maxRetries: 2)
        let item = h.item("a")
        try await h.outbox.enqueue(item)

        await h.outbox.noteAttempt(id: item.id, error: "replayed")
        let afterOne = try await h.stored(item)
        XCTAssertEqual(afterOne?.syncStatus, .pending)
        XCTAssertEqual(afterOne?.retryCount, 1)

        await h.outbox.noteAttempt(id: item.id, error: "replayed")
        let afterTwo = try await h.stored(item)
        XCTAssertEqual(afterTwo?.syncStatus, .failed, "An action the server never answers is not replayed forever")
    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
