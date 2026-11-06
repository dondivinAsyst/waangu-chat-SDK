import XCTest
@testable import WaanguFeatureChat

/// `CALL_DEVICE_TRANSFERRED` reaches every device of the user, including the one
/// that just answered — so this decision runs on the answering device too, and
/// getting it wrong hangs up the call at the moment it is accepted.
///
/// The two outcomes are not symmetric: keeping a call that really moved leaves a
/// stale screen the user can dismiss, while releasing one this device answered
/// is unrecoverable. Every uncertain case must therefore keep the call.
final class CallDeviceTransferTests: XCTestCase {

    func test_sameDeviceKeepsTheCall() {
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(
                toDeviceId: "device-a",
                thisDeviceId: "device-a"
            ),
            .keepCall
        )
    }

    func test_anotherDeviceReleasesTheCall() {
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(
                toDeviceId: "device-b",
                thisDeviceId: "device-a"
            ),
            .releaseCall
        )
    }

    /// The regression: the device id used to load asynchronously, so an event
    /// arriving first was compared against nothing and the answering device
    /// hung up on itself.
    func test_unknownOwnDeviceKeepsTheCall() {
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(toDeviceId: "device-b", thisDeviceId: nil),
            .keepCall
        )
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(toDeviceId: "device-b", thisDeviceId: ""),
            .keepCall
        )
    }

    func test_missingTargetKeepsTheCall() {
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(toDeviceId: nil, thisDeviceId: "device-a"),
            .keepCall
        )
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(toDeviceId: "", thisDeviceId: "device-a"),
            .keepCall
        )
    }

    /// `identifierForVendor` is uppercase while every other id on the wire is
    /// lowercase, so a case change in transit must not stop this device
    /// recognising itself.
    func test_deviceMatchIgnoresCase() {
        XCTAssertEqual(
            VoipManager.deviceTransferOutcome(
                toDeviceId: "47ad8f5f-6a97-4eef-a291-b896a6e9bc1f",
                thisDeviceId: "47AD8F5F-6A97-4EEF-A291-B896A6E9BC1F"
            ),
            .keepCall
        )
    }
}
