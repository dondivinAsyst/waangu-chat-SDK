import XCTest
@testable import WaanguFeatureChat

final class ScreenShareStateTests: XCTestCase {

    // MARK: - Already-sharing rejection

    func test_alreadySharingErrorIsRecognisedByMessageNotCode() {
        // CALL-INTEGRATION.md §9.3 :700-717 — the already-sharing rejection is a
        // free-text CALL_ERROR with no dedicated code. Matching on `code` here
        // would silently never fire.
        XCTAssertTrue(
            VoipManager.isAlreadySharingError(
                code: nil,
                message: "Another participant is already sharing screen"
            )
        )
    }

    func test_alreadySharingMatchIsCaseInsensitive() {
        XCTAssertTrue(
            VoipManager.isAlreadySharingError(
                code: "SOME_OTHER_CODE",
                message: "another participant is ALREADY SHARING SCREEN"
            )
        )
    }

    func test_unrelatedErrorsAreNotTreatedAsScreenShareRejections() {
        // These must fall through to the generic path, which ends the call.
        XCTAssertFalse(
            VoipManager.isAlreadySharingError(code: "LOCK_BUSY", message: "Join/reject concurrent")
        )
        XCTAssertFalse(
            VoipManager.isAlreadySharingError(
                code: "CORE_INITIATE_FAILED",
                message: "gRPC initiateCall failed"
            )
        )
        XCTAssertFalse(VoipManager.isAlreadySharingError(code: nil, message: nil))
    }

    // MARK: - Camera restore

    func test_cameraIsRestoredOnlyIfItWasOnBeforeTheShare() {
        var state = ScreenShareCameraState()
        state.remember(wasCameraOn: true)
        XCTAssertTrue(state.shouldRestoreCamera)

        var offState = ScreenShareCameraState()
        offState.remember(wasCameraOn: false)
        XCTAssertFalse(
            offState.shouldRestoreCamera,
            "an audio call must not silently turn the camera on when a share ends"
        )
    }

    func test_clearForgetsTheRememberedCameraState() {
        var state = ScreenShareCameraState()
        state.remember(wasCameraOn: true)
        state.clear()
        XCTAssertFalse(state.shouldRestoreCamera)
    }

    func test_freshStateDoesNotRestoreCamera() {
        XCTAssertFalse(ScreenShareCameraState().shouldRestoreCamera)
    }
}
