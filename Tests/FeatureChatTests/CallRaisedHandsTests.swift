import XCTest
@testable import WaanguFeatureChat

/// The queue is what the host acts on, so its order is the feature. The server
/// owns that order whenever it sends one.
final class CallRaisedHandsTests: XCTestCase {

    func test_raiseAppendsInArrivalOrder() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        hands.raise("userC")
        XCTAssertEqual(hands.queue, ["userB", "userC"])
    }

    /// `REQUEST_TO_SPEAK` accompanies `HAND_RAISED` for the same act, so the
    /// same peer arriving twice must not take two slots.
    func test_raiseIsIdempotent() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        hands.raise("userB")
        XCTAssertEqual(hands.queue, ["userB"])
    }

    func test_raiseIgnoresEmptyPeerId() {
        var hands = CallRaisedHands()
        hands.raise("")
        XCTAssertTrue(hands.queue.isEmpty)
    }

    func test_lowerRemovesOnlyThatPeer() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        hands.raise("userC")
        hands.lower("userB")
        XCTAssertEqual(hands.queue, ["userC"])
    }

    func test_serverQueueReplacesLocalOrder() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        hands.raise("userC")
        hands.apply(serverQueue: ["userC", "userB"])
        XCTAssertEqual(hands.queue, ["userC", "userB"])
    }

    /// Not every event carries the queue; a nil must leave what we have alone
    /// rather than clearing the list.
    func test_nilServerQueueLeavesLocalStateUntouched() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        hands.apply(serverQueue: nil)
        XCTAssertEqual(hands.queue, ["userB"])
    }

    func test_containsReportsMembership() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        XCTAssertTrue(hands.contains("userB"))
        XCTAssertFalse(hands.contains("userC"))
    }

    func test_removeAllClearsQueue() {
        var hands = CallRaisedHands()
        hands.raise("userB")
        hands.removeAll()
        XCTAssertTrue(hands.queue.isEmpty)
    }
}
