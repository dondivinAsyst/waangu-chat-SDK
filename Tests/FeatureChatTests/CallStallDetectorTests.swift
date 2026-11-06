import XCTest
@testable import WaanguFeatureChat

/// Spotting a peer whose media has stopped arriving.
///
/// The bug these cover: a peer that loses the network keeps its consumer, its
/// track and its last decoded frame, so nothing in the media graph changes and
/// no event fires. Their tile froze on the last frame while the call carried on
/// counting, which reads as a healthy call. The only thing that does change is
/// the receiver's byte counter, which stops advancing — so that is what is
/// watched here.
final class CallStallDetectorTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func date(_ offset: TimeInterval) -> Date {
        start.addingTimeInterval(offset)
    }

    // MARK: - Stall detection

    func test_firstSampleIsNeverStalled() {
        var detector = CallStallDetector(threshold: 3)

        XCTAssertEqual(detector.update(bytes: ["c1": 0], now: date(0)), [])
    }

    func test_advancingCounterIsNotStalled() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100], now: date(0))
        _ = detector.update(bytes: ["c1": 200], now: date(1))

        XCTAssertEqual(detector.update(bytes: ["c1": 300], now: date(10)), [])
    }

    func test_flatCounterIsNotStalledBeforeTheThreshold() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100], now: date(0))

        XCTAssertEqual(detector.update(bytes: ["c1": 100], now: date(2.9)), [])
    }

    func test_flatCounterIsStalledOnceThresholdPasses() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100], now: date(0))

        XCTAssertEqual(detector.update(bytes: ["c1": 100], now: date(3)), ["c1"])
    }

    /// The whole point of the feature: media resumes, the tile comes back.
    func test_stalledConsumerRecoversWhenBytesMoveAgain() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100], now: date(0))
        XCTAssertEqual(detector.update(bytes: ["c1": 100], now: date(5)), ["c1"])

        XCTAssertEqual(detector.update(bytes: ["c1": 140], now: date(6)), [])
    }

    /// A consumer replaced under the same id restarts its counter. That is a
    /// fresh stream, not a stall, and calling it one would show "Reconnecting…"
    /// over a peer who just came back.
    func test_counterGoingBackwardsRestartsTheClock() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 900], now: date(0))
        XCTAssertEqual(detector.update(bytes: ["c1": 10], now: date(5)), [])
        XCTAssertEqual(detector.update(bytes: ["c1": 10], now: date(6)), [])
    }

    /// A closed consumer is gone, not stalled — and must not leave a timestamp
    /// behind that instantly condemns a consumer reopened under the same id.
    func test_disappearingConsumerIsForgotten() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100], now: date(0))
        XCTAssertEqual(detector.update(bytes: [:], now: date(5)), [])
        XCTAssertEqual(detector.update(bytes: ["c1": 100], now: date(6)), [])
    }

    func test_resetForgetsEverything() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100], now: date(0))
        detector.reset()

        XCTAssertEqual(detector.update(bytes: ["c1": 100], now: date(10)), [])
    }

    func test_tracksConsumersIndependently() {
        var detector = CallStallDetector(threshold: 3)

        _ = detector.update(bytes: ["c1": 100, "c2": 100], now: date(0))

        XCTAssertEqual(
            detector.update(bytes: ["c1": 100, "c2": 500], now: date(5)),
            ["c1"]
        )
    }

    // MARK: - Consumer → peer

    func test_peerIsStalledOnlyWhenEveryConsumerOfTheirsIs() {
        let owners = ["audio-a": "peer-a", "video-a": "peer-a"]

        XCTAssertEqual(
            CallStallDetector.stalledOwnerKeys(
                stalledConsumers: ["audio-a", "video-a"],
                consumerOwners: owners
            ),
            ["peer-a"]
        )
    }

    /// The camera-off case. A paused video consumer's counter never moves again,
    /// and judging the peer on that alone would put "Reconnecting…" over someone
    /// talking perfectly well on audio.
    func test_peerWithOneLiveStreamIsNotStalled() {
        let owners = ["audio-a": "peer-a", "video-a": "peer-a"]

        XCTAssertEqual(
            CallStallDetector.stalledOwnerKeys(
                stalledConsumers: ["video-a"],
                consumerOwners: owners
            ),
            []
        )
    }

    func test_onlyTheStalledPeerIsReported() {
        let owners = [
            "audio-a": "peer-a",
            "audio-b": "peer-b",
            "video-b": "peer-b"
        ]

        XCTAssertEqual(
            CallStallDetector.stalledOwnerKeys(
                stalledConsumers: ["audio-b", "video-b"],
                consumerOwners: owners
            ),
            ["peer-b"]
        )
    }

    func test_noConsumersMeansNobodyIsStalled() {
        XCTAssertEqual(
            CallStallDetector.stalledOwnerKeys(
                stalledConsumers: [],
                consumerOwners: [:]
            ),
            []
        )
    }
}
