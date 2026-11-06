import XCTest
@testable import WaanguFeatureChat

final class MediaViewerGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 400, height: 800)

    // MARK: - HeroGeometry

    func test_targetRect_landscapeImage_fitsWidthAndCentersVertically() {
        // 2:1 image in a 400x800 container -> 400x200, centered.
        let rect = HeroGeometry.targetRect(for: CGSize(width: 200, height: 100), in: screen)
        XCTAssertEqual(rect.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.height, 200, accuracy: 0.01)
        XCTAssertEqual(rect.midY, screen.midY, accuracy: 0.01)
    }

    func test_targetRect_portraitImage_fitsHeightAndCentersHorizontally() {
        // 1:4 image in a 400x800 container -> 200x800, centered.
        let rect = HeroGeometry.targetRect(for: CGSize(width: 100, height: 400), in: screen)
        XCTAssertEqual(rect.width, 200, accuracy: 0.01)
        XCTAssertEqual(rect.height, 800, accuracy: 0.01)
        XCTAssertEqual(rect.midX, screen.midX, accuracy: 0.01)
    }

    func test_targetRect_squareImage_fitsWidth() {
        let rect = HeroGeometry.targetRect(for: CGSize(width: 50, height: 50), in: screen)
        XCTAssertEqual(rect.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.height, 400, accuracy: 0.01)
    }

    func test_targetRect_zeroImageSize_fallsBackToBounds() {
        // A failed decode must not produce NaN geometry that breaks the animation.
        XCTAssertEqual(HeroGeometry.targetRect(for: .zero, in: screen), screen)
        XCTAssertEqual(HeroGeometry.targetRect(for: CGSize(width: 100, height: 0), in: screen), screen)
    }

    func test_targetRect_zeroBounds_fallsBackToBounds() {
        let empty = CGRect.zero
        XCTAssertEqual(HeroGeometry.targetRect(for: CGSize(width: 10, height: 10), in: empty), empty)
    }

    // MARK: - DismissDecision

    func test_outcome_finishesPastTranslationThreshold() {
        let outcome = DismissDecision.outcome(
            translation: CGSize(width: 0, height: 150),
            velocity: .zero
        )
        XCTAssertEqual(outcome, .finish)
    }

    func test_outcome_finishesOnFlickEvenWithSmallTranslation() {
        let outcome = DismissDecision.outcome(
            translation: CGSize(width: 0, height: 20),
            velocity: CGSize(width: 0, height: 900)
        )
        XCTAssertEqual(outcome, .finish)
    }

    func test_outcome_finishesOnUpwardDrag() {
        // Dragging up dismisses too, matching the previous carousel and WhatsApp.
        let outcome = DismissDecision.outcome(
            translation: CGSize(width: 0, height: -150),
            velocity: .zero
        )
        XCTAssertEqual(outcome, .finish)
    }

    func test_outcome_cancelsBelowBothThresholds() {
        let outcome = DismissDecision.outcome(
            translation: CGSize(width: 0, height: 40),
            velocity: CGSize(width: 0, height: 100)
        )
        XCTAssertEqual(outcome, .cancel)
    }

    func test_outcome_ignoresHorizontalMotion() {
        // Horizontal drag belongs to the pager, never to dismiss.
        let outcome = DismissDecision.outcome(
            translation: CGSize(width: 400, height: 10),
            velocity: CGSize(width: 2000, height: 0)
        )
        XCTAssertEqual(outcome, .cancel)
    }

    func test_progress_isClampedToOne() {
        XCTAssertEqual(
            DismissDecision.progress(translation: CGSize(width: 0, height: 2000), in: screen),
            1.0,
            accuracy: 0.001
        )
    }

    func test_progress_isHalfAtHalfTravel() {
        // Travel is measured against half the container height.
        let p = DismissDecision.progress(translation: CGSize(width: 0, height: 200), in: screen)
        XCTAssertEqual(p, 0.5, accuracy: 0.001)
    }

    func test_progress_zeroBounds_isZero() {
        XCTAssertEqual(DismissDecision.progress(translation: CGSize(width: 0, height: 100), in: .zero), 0)
    }

    func test_scale_shrinksButNeverBelowFloor() {
        XCTAssertEqual(DismissDecision.scale(forProgress: 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(DismissDecision.scale(forProgress: 1), 0.6, accuracy: 0.001)
    }

    // MARK: - ZoomMath

    func test_zoomRect_isCenteredOnTapPoint() {
        let rect = ZoomMath.zoomRect(
            scale: 2,
            center: CGPoint(x: 100, y: 200),
            in: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(rect.width, 200, accuracy: 0.01)
        XCTAssertEqual(rect.height, 400, accuracy: 0.01)
        XCTAssertEqual(rect.midX, 100, accuracy: 0.01)
        XCTAssertEqual(rect.midY, 200, accuracy: 0.01)
    }

    func test_zoomRect_nonPositiveScale_returnsFullBounds() {
        let rect = ZoomMath.zoomRect(scale: 0, center: .zero, in: CGSize(width: 400, height: 800))
        XCTAssertEqual(rect, CGRect(origin: .zero, size: CGSize(width: 400, height: 800)))
    }

    func test_centeringInset_padsSmallerContent() {
        let inset = ZoomMath.centeringInset(
            contentSize: CGSize(width: 400, height: 200),
            boundsSize: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(inset.top, 300, accuracy: 0.01)
        XCTAssertEqual(inset.bottom, 300, accuracy: 0.01)
        XCTAssertEqual(inset.left, 0, accuracy: 0.01)
    }

    func test_centeringInset_isZeroWhenContentExceedsBounds() {
        let inset = ZoomMath.centeringInset(
            contentSize: CGSize(width: 900, height: 1600),
            boundsSize: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(inset, .zero)
    }
}
