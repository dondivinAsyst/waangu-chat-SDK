import XCTest
@testable import WaanguScreenShareTransport

final class FrameRateLimiterTests: XCTestCase {

    private let oneSecond: UInt64 = 1_000_000_000

    func test_firstFrameIsAlwaysAdmitted() {
        var limiter = FrameRateLimiter(framesPerSecond: 15)
        XCTAssertTrue(limiter.shouldSend(at: 0))
    }

    func test_frameArrivingTooSoonIsDropped() {
        var limiter = FrameRateLimiter(framesPerSecond: 15)
        XCTAssertTrue(limiter.shouldSend(at: 0))
        // 1/60 s — well inside the 1/15 s interval.
        XCTAssertFalse(limiter.shouldSend(at: oneSecond / 60))
    }

    func test_frameAtTheIntervalIsAdmitted() {
        var limiter = FrameRateLimiter(framesPerSecond: 15)
        XCTAssertTrue(limiter.shouldSend(at: 0))
        XCTAssertTrue(limiter.shouldSend(at: oneSecond / 15))
    }

    func test_sixtyFpsInputIsThinnedToFifteen() {
        var limiter = FrameRateLimiter(framesPerSecond: 15)
        let admitted = (0..<60).filter { index in
            limiter.shouldSend(at: UInt64(index) * oneSecond / 60)
        }.count
        XCTAssertEqual(admitted, 15)
    }

    func test_clockGoingBackwardsDoesNotStallTheStream() {
        // ReplayKit timestamps are monotonic, but a restarted broadcast reuses
        // the clock. A backwards jump must not wedge the limiter shut forever.
        var limiter = FrameRateLimiter(framesPerSecond: 15)
        XCTAssertTrue(limiter.shouldSend(at: 10 * oneSecond))
        XCTAssertTrue(limiter.shouldSend(at: 0))
    }
}
