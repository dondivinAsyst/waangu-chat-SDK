import XCTest
@testable import WaanguFeatureChat

final class BubbleCallStyleTests: XCTestCase {

    func test_negativeToneIsReservedForMissedAndFailed() {
        XCTAssertEqual(BubbleCallTone.forOutcome(.missed, isMissedFallback: false), .danger)
        XCTAssertEqual(BubbleCallTone.forOutcome(.failed, isMissedFallback: false), .danger)
    }

    func test_neutralToneIsUsedForNonNegativeOutcomes() {
        XCTAssertEqual(BubbleCallTone.forOutcome(.answered, isMissedFallback: false), .neutral)
        XCTAssertEqual(BubbleCallTone.forOutcome(.declined, isMissedFallback: false), .neutral)
        XCTAssertEqual(BubbleCallTone.forOutcome(.busy, isMissedFallback: false), .neutral)
        XCTAssertEqual(BubbleCallTone.forOutcome(.noAnswer, isMissedFallback: false), .neutral)
        XCTAssertEqual(BubbleCallTone.forOutcome(.cancelled, isMissedFallback: false), .neutral)
    }

    func test_legacyMissedFallbackStillUsesDangerTone() {
        XCTAssertEqual(BubbleCallTone.forOutcome(nil, isMissedFallback: true), .danger)
        XCTAssertEqual(BubbleCallTone.forOutcome(nil, isMissedFallback: false), .neutral)
    }
}
