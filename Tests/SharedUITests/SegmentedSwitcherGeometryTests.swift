import XCTest
@testable import WaanguSharedUI

final class SegmentedSwitcherGeometryTests: XCTestCase {

    private let segment: CGFloat = 120
    private let count = 3

    private func snap(from: Int, translation: CGFloat, overshoot: CGFloat = 0) -> Int {
        SegmentedSwitcherGeometry.snapIndex(
            from: from,
            translation: translation,
            segmentWidth: segment,
            predictedOvershoot: overshoot,
            count: count
        )
    }

    func test_shortDrag_doesNotCommit() {
        XCTAssertEqual(snap(from: 1, translation: -20), 1)
    }

    func test_dragLeftPastHalf_advances() {
        XCTAssertEqual(snap(from: 0, translation: -80), 1)
    }

    func test_dragRightPastHalf_goesBack() {
        XCTAssertEqual(snap(from: 2, translation: 80), 1)
    }

    func test_flick_commitsDespiteShortDistance() {
        XCTAssertEqual(snap(from: 0, translation: -10, overshoot: -200), 1)
    }

    func test_distanceBeatsOvershoot_whenBothPresent() {
        // Finger clearly travelled right; a leftward predicted overshoot must not
        // flip the direction.
        XCTAssertEqual(snap(from: 2, translation: 90, overshoot: -200), 1)
    }

    func test_clampsAtFirstSegment() {
        XCTAssertEqual(snap(from: 0, translation: 200), 0)
    }

    func test_clampsAtLastSegment() {
        XCTAssertEqual(snap(from: 2, translation: -200), 2)
    }

    func test_zeroSegmentWidth_isSafe() {
        let result = SegmentedSwitcherGeometry.snapIndex(
            from: 1, translation: -200, segmentWidth: 0, predictedOvershoot: -200, count: count
        )
        XCTAssertEqual(result, 1)
    }

    func test_emptyCount_isSafe() {
        let result = SegmentedSwitcherGeometry.snapIndex(
            from: 0, translation: -200, segmentWidth: segment, predictedOvershoot: 0, count: 0
        )
        XCTAssertEqual(result, 0)
    }

    func test_progress_saturatesAtOne() {
        XCTAssertEqual(SegmentedSwitcherGeometry.progress(translation: -240, segmentWidth: segment), 1)
        XCTAssertEqual(SegmentedSwitcherGeometry.progress(translation: -60, segmentWidth: segment), 0.5)
    }

    func test_rubberBand_resistsAndPreservesSign() {
        let pulled = SegmentedSwitcherGeometry.rubberBanded(100, limit: 300)
        XCTAssertGreaterThan(pulled, 0)
        XCTAssertLessThan(pulled, 100)
        XCTAssertEqual(SegmentedSwitcherGeometry.rubberBanded(-100, limit: 300), -pulled, accuracy: 0.001)
    }
}
