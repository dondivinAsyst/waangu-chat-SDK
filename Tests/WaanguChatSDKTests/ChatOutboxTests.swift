//
//  ChatOutboxTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.9 — the outbox adapter and the flush handler, moved from the Waangu app
//  target. They had no tests there.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
import WaanguFeatureChat
@testable import WaanguChatSDK

// MARK: - Flush handler

final class ChatOutboxFlushTests: XCTestCase {

    private func item(_ name: String) -> ChatOutboxItem {
        ChatOutboxItem(actionType: .sendMessage, payload: Data("{}".utf8),
                       idempotencyKey: "send_message:\(name)", conversationId: "c",
                       createdAt: Date(), syncStatus: .pending)
    }

    private func response(_ json: String) throws -> ChatOutboxBatchResponseDTO {
        try JSONDecoder().decode(ChatOutboxBatchResponseDTO.self, from: Data(json.utf8))
    }

    func test_theServersAnswer_isReportedPerItem() async throws {
        let first = item("a"), second = item("b")
        let answer = try response("""
        {"syncTimestamp": 1, "results": [
          {"localId": "\(first.id)", "success": true, "serverId": "S1"},
          {"localId": "\(second.id)", "success": false, "error": "refused", "errorCode": "E1", "retryable": false}
        ]}
        """)
        let handler = ChatOutboxFlush.makeHandler { StubAPIClient(response: answer) }

        let results = try await handler([first, second])

        XCTAssertEqual(results.map(\.localId), [first.id, second.id])
        XCTAssertEqual(results.map(\.success), [true, false])
        XCTAssertEqual(results[0].serverId, "S1")
        XCTAssertEqual(results[1].error, "refused")
        XCTAssertEqual(results[1].retryable, false)
    }

    /// A request that fails does not lose the batch: every item comes back failed, with the error.
    func test_aFailedRequest_failsEveryItemOfTheBatch() async throws {
        let batch = [item("a"), item("b"), item("c")]
        let handler = ChatOutboxFlush.makeHandler { StubAPIClient(failure: StubError.unreachable) }

        let results = try await handler(batch)

        XCTAssertEqual(results.map(\.localId), batch.map(\.id))
        XCTAssertEqual(results.map(\.success), [false, false, false])
        XCTAssertEqual(Set(results.compactMap(\.error)), ["server unreachable"])
    }

    func test_aClientThatCannotBeBuilt_failsEveryItemToo() async throws {
        let batch = [item("a"), item("b")]
        let handler = ChatOutboxFlush.makeHandler { throw StubError.unreachable }

        let results = try await handler(batch)

        XCTAssertEqual(results.map(\.success), [false, false])
    }

    func test_theClientIsAskedForEachBatch() async throws {
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        let answer = try response(#"{"syncTimestamp": 1, "results": []}"#)
        let handler = ChatOutboxFlush.makeHandler { count.n += 1; return StubAPIClient(response: answer) }

        _ = try await handler([item("a")])
        _ = try await handler([item("b")])

        XCTAssertEqual(count.n, 2)
    }
}

// MARK: - Adapter

final class ChatOutboxAdapterTests: XCTestCase {

    private func makeOutbox() async -> (DatabaseOutbox<ChatOutboxItem>, any DatabaseRepositoryProtocol) {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        let outbox = DatabaseOutbox<ChatOutboxItem>(database: store, config: .default) { batch in
            batch.map { OutboxFlushResult(localId: $0.id, success: true) }
        }
        return (outbox, store)
    }

    /// The same shape the item factories build their keys from: `<action>:<reference>`.
    private func queued(_ reference: String) -> ChatOutboxItem {
        ChatOutboxItem(actionType: .sendMessage, payload: Data("{}".utf8),
                       idempotencyKey: "\(ChatOutboxItemActionType.sendMessage.rawValue):\(reference)",
                       conversationId: "c", createdAt: Date(), syncStatus: .pending)
    }

    func test_enqueue_putsTheActionInTheOutbox() async throws {
        let (outbox, store) = await makeOutbox()
        let adapter = ChatOutboxAdapter(outbox: outbox)
        let action = queued("ref-\(UUID().uuidString)")

        try await adapter.enqueue(action)

        let stored = try await store.fetchOne(ChatOutboxItem.self, id: action.id)
        XCTAssertEqual(stored?.idempotencyKey, action.idempotencyKey)
        XCTAssertEqual(stored?.syncStatus, .pending)
    }

    func test_anAcknowledgement_settlesTheMatchingAction() async throws {
        let (outbox, store) = await makeOutbox()
        let adapter = ChatOutboxAdapter(outbox: outbox)
        let reference = "ref-\(UUID().uuidString)"
        let action = queued(reference)
        try await adapter.enqueue(action)

        let settled = await adapter.settle(.sendMessage, reference: reference, as: .acknowledged)

        XCTAssertEqual(settled, 1)
        let stored = try await store.fetchOne(ChatOutboxItem.self, id: action.id)
        XCTAssertEqual(stored?.syncStatus, .synced)
    }

    func test_aRefusal_failsTheActionWithTheServersReason() async throws {
        let (outbox, store) = await makeOutbox()
        let adapter = ChatOutboxAdapter(outbox: outbox)
        let reference = "ref-\(UUID().uuidString)"
        let action = queued(reference)
        try await adapter.enqueue(action)

        let settled = await adapter.settle(.sendMessage, reference: reference, as: .rejected(reason: "blocked"))

        XCTAssertEqual(settled, 1)
        let stored = try await store.fetchOne(ChatOutboxItem.self, id: action.id)
        XCTAssertEqual(stored?.syncStatus, .failed)
        XCTAssertEqual(stored?.lastError, "blocked")
    }

    func test_anAcknowledgementForAnotherAction_changesNothing() async throws {
        let (outbox, store) = await makeOutbox()
        let adapter = ChatOutboxAdapter(outbox: outbox)
        let action = queued("ref-\(UUID().uuidString)")
        try await adapter.enqueue(action)

        let settled = await adapter.settle(.deleteMessage, reference: "unrelated-\(UUID().uuidString)", as: .acknowledged)

        XCTAssertEqual(settled, 0)
        let stored = try await store.fetchOne(ChatOutboxItem.self, id: action.id)
        XCTAssertEqual(stored?.syncStatus, .pending)
    }

    func test_pendingOlderThan_listsOnlyOldPendingActions() async throws {
        let (outbox, _) = await makeOutbox()
        let adapter = ChatOutboxAdapter(outbox: outbox)
        let tag = UUID().uuidString
        let old = ChatOutboxItem(actionType: .sendMessage, payload: Data("{}".utf8),
                                 idempotencyKey: "send_message:old-\(tag)", conversationId: "c",
                                 createdAt: Date().addingTimeInterval(-600), syncStatus: .pending)
        let fresh = queued("fresh-\(tag)")
        try await adapter.enqueue(old)
        try await adapter.enqueue(fresh)

        let listed = await adapter.pending(olderThan: 300)

        XCTAssertTrue(listed.contains { $0.id == old.id })
        XCTAssertFalse(listed.contains { $0.id == fresh.id })
    }
}
