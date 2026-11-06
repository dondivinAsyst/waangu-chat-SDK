//
//  ChatSyncRunnerTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13 — `ChatSyncRunner` : flush puis pull, une synchro à la fois,
//  arrêt sur demande.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatSyncRunnerTests: XCTestCase {

    func test_syncNow_flushesTheOutboxThenPullsMissedEvents() async {
        let sync = RecordingSync()
        let runner = ChatSyncRunner(sync: sync)

        await runner.syncNow()

        let calls = await sync.calls
        XCTAssertEqual(calls, ["flush", "pull"])
    }

    func test_syncNow_whileAnotherRuns_isIgnored() async throws {
        let sync = RecordingSync(holdFirstFlush: true)
        let runner = ChatSyncRunner(sync: sync)

        let first = Task { await runner.syncNow() }
        while await sync.calls.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        await runner.syncNow()          // runs while the first is held in flush
        await sync.release()
        await first.value

        let calls = await sync.calls
        XCTAssertEqual(calls, ["flush", "pull"], "The second call must not start another sync")
    }

    func test_syncNow_canRunAgainOnceTheFirstIsDone() async {
        let sync = RecordingSync()
        let runner = ChatSyncRunner(sync: sync)

        await runner.syncNow()
        await runner.syncNow()

        let calls = await sync.calls
        XCTAssertEqual(calls, ["flush", "pull", "flush", "pull"])
    }

    func test_isDegraded_isFalseByDefault_andForwardsTheSyncsAnswer() async {
        let plain = ChatSyncRunner(sync: RecordingSync())
        let degraded = await plain.isDegraded()
        XCTAssertFalse(degraded, "A sync that does not track it is never degraded")

        let reporting = ChatSyncRunner(sync: DegradedSync())
        let forwarded = await reporting.isDegraded()
        XCTAssertTrue(forwarded)
    }

    func test_stop_cancelsTheSync() async {
        let sync = RecordingSync()
        let runner = ChatSyncRunner(sync: sync)

        await runner.stop()

        let calls = await sync.calls
        XCTAssertEqual(calls, ["stop"])
    }
}

private actor RecordingSync: FeatureSyncProtocol {
    nonisolated let featureName = "recording"
    nonisolated let syncPriority: SyncPriority = .high
    private(set) var calls: [String] = []
    private var holdFirstFlush: Bool
    private var gate: CheckedContinuation<Void, Never>?

    init(holdFirstFlush: Bool = false) { self.holdFirstFlush = holdFirstFlush }

    func flushOutbox() async {
        calls.append("flush")
        if holdFirstFlush {
            holdFirstFlush = false
            await withCheckedContinuation { gate = $0 }
        }
    }
    func pullMissedEvents() async { calls.append("pull") }
    func stopSync() async { calls.append("stop") }
    func release() { gate?.resume(); gate = nil }
}

private struct DegradedSync: FeatureSyncProtocol {
    let featureName = "degraded"
    let syncPriority: SyncPriority = .high
    func flushOutbox() async {}
    func pullMissedEvents() async {}
    func stopSync() async {}
    func isDegraded() async -> Bool { true }
}
