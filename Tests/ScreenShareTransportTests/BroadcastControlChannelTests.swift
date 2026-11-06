import XCTest
@testable import WaanguScreenShareTransport

final class BroadcastControlChannelTests: XCTestCase {

    func test_postedStopRequestReachesObserver() {
        let stopped = expectation(description: "observer fired")
        let token = BroadcastControlChannel.observeStopRequests { stopped.fulfill() }
        XCTAssertNotEqual(token, BroadcastControlChannel.invalidToken, "registration failed")
        defer { BroadcastControlChannel.removeObserver(token) }

        BroadcastControlChannel.requestStop()

        wait(for: [stopped], timeout: 5)
    }

    func test_removedObserverStopsReceiving() {
        let lock = NSLock()
        var fireCount = 0

        let token = BroadcastControlChannel.observeStopRequests {
            lock.lock()
            fireCount += 1
            lock.unlock()
        }
        XCTAssertNotEqual(token, BroadcastControlChannel.invalidToken)
        BroadcastControlChannel.removeObserver(token)

        BroadcastControlChannel.requestStop()

        // Darwin notifications are asynchronous; give the queue time to be wrong.
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        lock.lock()
        XCTAssertEqual(fireCount, 0)
        lock.unlock()
    }

    func test_removingAnInvalidTokenIsSafe() {
        // Teardown paths call this unconditionally, including when registration
        // never succeeded.
        XCTAssertNoThrow(
            BroadcastControlChannel.removeObserver(BroadcastControlChannel.invalidToken)
        )
    }

    func test_stopIsIdempotent() {
        // Coalescing is the reason this mechanism is acceptable for stop and not
        // for frames: repeated posts must not misbehave.
        let stopped = expectation(description: "observer fired at least once")
        stopped.assertForOverFulfill = false

        let token = BroadcastControlChannel.observeStopRequests { stopped.fulfill() }
        defer { BroadcastControlChannel.removeObserver(token) }

        BroadcastControlChannel.requestStop()
        BroadcastControlChannel.requestStop()
        BroadcastControlChannel.requestStop()

        wait(for: [stopped], timeout: 5)
    }
}
