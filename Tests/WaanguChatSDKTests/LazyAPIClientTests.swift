//
//  LazyAPIClientTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.9 — the client that is created when a call needs it. It was
//  `ChatAPIClientProxy`, tied to the Waangu app's container.
//

import XCTest
import WaanguCoreKit
import WaanguFeatureChat
@testable import WaanguChatSDK

final class LazyAPIClientTests: XCTestCase {

    private let endpoint = HTTPChatSyncEndpoints.flushOutbox(ChatOutboxBatchRequestDTO(actions: []))

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int { lock.withLock { _value } }
        func bump() { lock.withLock { _value += 1 } }
    }

    func test_nothingIsBuilt_untilACallNeedsTheClient() {
        let built = Counter()
        _ = LazyAPIClient { built.bump(); return StubAPIClient() }

        XCTAssertEqual(built.value, 0)
    }

    func test_eachCall_asksForTheCurrentClient() async throws {
        let built = Counter()
        let client = LazyAPIClient { built.bump(); return StubAPIClient(response: "ok") }

        let first: String = try await client.request(endpoint: endpoint)
        let second: String = try await client.request(endpoint: endpoint)

        XCTAssertEqual([first, second], ["ok", "ok"])
        XCTAssertEqual(built.value, 2, "a client replaced after a login must be the one used")
    }

    func test_calls_areForwardedToTheRealClient() async {
        let real = StubAPIClient(connected: true)
        let client = LazyAPIClient { real }

        let connected = await client.isConnected
        await client.cancelAllRequests()
        let metrics = await client.getPerformanceMetrics()

        XCTAssertTrue(connected)
        XCTAssertEqual(real.cancelAllCount, 1)
        XCTAssertEqual(metrics.totalRequests, 7)
    }

    func test_whenTheClientCannotBeBuilt_requestsThrowTheSameError() async {
        let client = LazyAPIClient { throw StubError.unreachable }

        do {
            let _: String = try await client.request(endpoint: endpoint)
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error as? StubError, .unreachable)
        }
    }

    func test_whenTheClientCannotBeBuilt_readOnlyCallsAnswerNeutrally() async {
        let client = LazyAPIClient { throw StubError.unreachable }

        let connected = await client.isConnected
        await client.cancelAllRequests()
        let metrics = await client.getPerformanceMetrics()

        XCTAssertFalse(connected)
        XCTAssertEqual(metrics.totalRequests, 0)
        XCTAssertEqual(metrics.successCount, 0)
    }
}
