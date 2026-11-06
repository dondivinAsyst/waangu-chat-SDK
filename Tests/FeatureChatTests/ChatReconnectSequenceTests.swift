//
//  ChatReconnectSequenceTests.swift
//  FeatureChatTests
//
//  Bloc 8 §20 / B64 — the reconnect work runs as one ordered routine.
//

import XCTest
@testable import WaanguFeatureChat

final class ChatReconnectSequenceTests: XCTestCase {

    /// Records the order in which the steps actually ran.
    private actor Recorder {
        private(set) var calls: [String] = []
        func add(_ name: String) { calls.append(name) }
    }

    private struct Boom: Error {}

    private func makeSequence(
        recorder: Recorder,
        needsReauthentication: @escaping @Sendable () async throws -> Bool = { false },
        deltaSync: (@Sendable () async throws -> Void)? = nil,
        minimumDeltaSyncInterval: TimeInterval = 30,
        deltaSyncTimeout: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> ChatReconnectSequence {
        ChatReconnectSequence(
            steps: .init(
                needsReauthentication: {
                    await recorder.add("reauthenticate")
                    return try await needsReauthentication()
                },
                deltaSync: {
                    await recorder.add("deltaSync")
                    try await deltaSync?()
                },
                reconcileFinance: { await recorder.add("refreshFinancialState") },
                drainFinanceOutbox: { await recorder.add("drainFinanceOutbox") },
                drainChatOutbox: { await recorder.add("drainChatOutbox") }
            ),
            minimumDeltaSyncInterval: minimumDeltaSyncInterval,
            deltaSyncTimeout: deltaSyncTimeout,
            now: now
        )
    }

    func test_connectionEdges_decideWhatRuns() {
        typealias S = ChatReconnectSequence
        // First connection after launch, seen right away.
        XCTAssertEqual(S.trigger(wasConnected: false, hasConnectedBefore: false, isConnected: true), .startup)
        // First connection after launch, after a disconnected / connecting state: still a startup,
        // never a second sync next to the one the chat start runs.
        XCTAssertEqual(S.trigger(wasConnected: false, hasConnectedBefore: false, isConnected: true), .startup)
        // A real transition back after having been connected.
        XCTAssertEqual(S.trigger(wasConnected: false, hasConnectedBefore: true, isConnected: true), .reconnect)
        // The stream republishes the state: staying connected never retriggers.
        XCTAssertNil(S.trigger(wasConnected: true, hasConnectedBefore: true, isConnected: true))
        XCTAssertNil(S.trigger(wasConnected: true, hasConnectedBefore: true, isConnected: false))
        // Connecting / authenticating states do nothing.
        XCTAssertNil(S.trigger(wasConnected: false, hasConnectedBefore: true, isConnected: false))
        XCTAssertNil(S.trigger(wasConnected: false, hasConnectedBefore: false, isConnected: false))
    }

    func test_reconnect_runsTheStepsInTheSpecifiedOrder() async {
        let recorder = Recorder()
        let sequence = makeSequence(recorder: recorder)

        let report = await sequence.run(.reconnect)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["reauthenticate", "deltaSync", "refreshFinancialState", "drainFinanceOutbox", "drainChatOutbox"])
        XCTAssertEqual(report?.result, .finished)
        XCTAssertEqual(report?.ranInOrder.map(\.rawValue), calls)
    }

    func test_stepsWithoutAContract_areReportedSkipped_neverInvented() async {
        let recorder = Recorder()
        let report = await makeSequence(recorder: recorder).run(.reconnect)

        for step in [ChatReconnectSequence.Step.refreshMembership, .refreshPolicy, .refreshCapability, .refreshFCO] {
            guard case .skipped? = report?.outcome(of: step) else {
                return XCTFail("\(step) must be skipped while its contract is missing")
            }
        }
    }

    func test_startup_onlyDrainsTheChatOutbox() async {
        let recorder = Recorder()
        let report = await makeSequence(recorder: recorder).run(.startup)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["drainChatOutbox"], "the chat start already syncs and reconciles")
        XCTAssertEqual(report?.result, .finished)
    }

    func test_aSessionThatNeedsReauthentication_stopsTheRoutine() async {
        let recorder = Recorder()
        let sequence = makeSequence(recorder: recorder, needsReauthentication: { true })

        let report = await sequence.run(.reconnect)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["reauthenticate"], "nothing may run on a stale session")
        XCTAssertEqual(report?.result, .stoppedForReauthentication)
    }

    func test_aFailingSync_doesNotHoldBackReconciliationOrTheOutbox() async {
        let recorder = Recorder()
        let sequence = makeSequence(recorder: recorder, deltaSync: { throw Boom() })

        let report = await sequence.run(.reconnect)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["reauthenticate", "deltaSync", "refreshFinancialState", "drainFinanceOutbox", "drainChatOutbox"])
        guard case .failed? = report?.outcome(of: .deltaSync) else {
            return XCTFail("the failed sync must be reported as failed")
        }
        XCTAssertEqual(report?.result, .finished)
    }

    func test_aSessionCheckThatThrows_doesNotHoldBackTheRest() async {
        let recorder = Recorder()
        let sequence = makeSequence(recorder: recorder, needsReauthentication: { throw Boom() })

        let report = await sequence.run(.reconnect)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["reauthenticate", "deltaSync", "refreshFinancialState", "drainFinanceOutbox", "drainChatOutbox"])
        XCTAssertEqual(report?.result, .finished)
    }

    func test_aSyncThatNeverAnswers_timesOut_andTheOutboxStillDrains() async {
        let recorder = Recorder()
        let sequence = makeSequence(
            recorder: recorder,
            deltaSync: { try await Task.sleep(nanoseconds: 30_000_000_000) },
            deltaSyncTimeout: 0.2
        )

        let report = await sequence.run(.reconnect)

        XCTAssertEqual(report?.outcome(of: .deltaSync), .timedOut)
        let calls = await recorder.calls
        XCTAssertEqual(calls.suffix(2), ["drainFinanceOutbox", "drainChatOutbox"])
    }

    func test_aFlappingConnection_doesNotRepeatTheDeltaSyncWithinTheMinimumInterval() async {
        let recorder = Recorder()
        let clock = ManualClock()
        let sequence = makeSequence(recorder: recorder, minimumDeltaSyncInterval: 30, now: { clock.now })

        await sequence.run(.reconnect)
        clock.advance(by: 10)
        let second = await sequence.run(.reconnect)

        let syncs = await recorder.calls.filter { $0 == "deltaSync" }.count
        XCTAssertEqual(syncs, 1, "second reconnect 10 s later must not sync again")
        guard case .skipped? = second?.outcome(of: .deltaSync) else {
            return XCTFail("the second sync must be reported skipped")
        }
        // The outbox is still drained both times: only the sync is rate limited.
        let drains = await recorder.calls.filter { $0 == "drainChatOutbox" }.count
        XCTAssertEqual(drains, 2)

        clock.advance(by: 25)
        await sequence.run(.reconnect)
        let after = await recorder.calls.filter { $0 == "deltaSync" }.count
        XCTAssertEqual(after, 2, "35 s after the first sync it runs again")
    }

    func test_twoOverlappingRuns_doNotReplayTheOutboxTwice() async {
        let recorder = Recorder()
        let sequence = makeSequence(recorder: recorder, deltaSync: { try await Task.sleep(nanoseconds: 300_000_000) })

        async let first = sequence.run(.reconnect)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let second = await sequence.run(.reconnect)
        _ = await first

        XCTAssertNil(second, "a run started while another is in progress is ignored")
        let drains = await recorder.calls.filter { $0 == "drainChatOutbox" }.count
        XCTAssertEqual(drains, 1)
    }
}

/// A clock the test moves by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
