import XCTest
@testable import WaanguFeatureChat

/// Local teardowns (CallKit killing a Simulator ring, ring timeout, hangup)
/// must publish reject/disconnect — otherwise the far end keeps ringing.
final class CallLocalEndSignalTests: XCTestCase {

    func test_incomingStillRingingRejects() {
        XCTAssertEqual(
            VoipManager.localEndSignal(
                hasNotifiedServer: false,
                isIncoming: true,
                wasAnswered: false
            ),
            .reject(reason: "declined")
        )
    }

    func test_incomingAfterAnswerDisconnects() {
        XCTAssertEqual(
            VoipManager.localEndSignal(
                hasNotifiedServer: false,
                isIncoming: true,
                wasAnswered: true
            ),
            .disconnect
        )
    }

    func test_outgoingCancelsWithDisconnect() {
        XCTAssertEqual(
            VoipManager.localEndSignal(
                hasNotifiedServer: false,
                isIncoming: false,
                wasAnswered: false
            ),
            .disconnect
        )
    }

    func test_alreadyNotifiedPublishesNothing() {
        XCTAssertNil(
            VoipManager.localEndSignal(
                hasNotifiedServer: true,
                isIncoming: true,
                wasAnswered: false
            )
        )
    }
}
