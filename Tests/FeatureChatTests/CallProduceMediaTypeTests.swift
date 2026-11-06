import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class CallProduceMediaTypeTests: XCTestCase {

    func test_screenMediaTypeIsDistinctFromVideoKind() {
        // The whole point of the field: kind stays "video" so the SFU treats it
        // as a video track, while mediaType tells peers it is a screen.
        // CALL-INTEGRATION.md §9.2 :634-637.
        XCTAssertEqual(CallMediaType.screen.rawValue, "screen")
        XCTAssertEqual(CallMediaType.video.rawValue, "video")
        XCTAssertEqual(CallMediaType.audio.rawValue, "audio")
        XCTAssertNotEqual(CallMediaType.screen.rawValue, CallMediaType.video.rawValue)
    }

    func test_produceDTO_carriesScreenMediaTypeWithVideoKind() throws {
        let parameters = try XCTUnwrap(RawJSONPayload(jsonString: "{}"))
        let dto = CallProduceDTO(
            sessionId: "sess-1",
            roomId: "room-1",
            peerId: "userA",
            transportId: "transport-1",
            kind: CallMediaKind.video.rawValue,
            rtpParameters: parameters,
            mediaType: CallMediaType.screen.rawValue
        )

        let encoded = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        // CALL-INTEGRATION.md §5 :266-278.
        XCTAssertEqual(json["kind"] as? String, "video")
        XCTAssertEqual(json["mediaType"] as? String, "screen")
    }

    func test_localProducerIdFallbackIsNamedForMediaTypeNotKind() {
        // Camera and screen are both kind "video"; naming the fallback id after
        // kind alone makes two indistinguishable ids in the logs.
        let screen = CallSignalingRepository.localProducerId(for: .screen)
        let video = CallSignalingRepository.localProducerId(for: .video)

        XCTAssertTrue(screen.hasPrefix("local-screen-"), screen)
        XCTAssertTrue(video.hasPrefix("local-video-"), video)
        XCTAssertNotEqual(screen, video)
    }

    func test_localProducerIdIsLowercase() {
        // Project rule: ids crossing a boundary are lowercase, because the same
        // UUID emitted in two cases produces two strings that never compare equal.
        let id = CallSignalingRepository.localProducerId(for: .screen)
        XCTAssertEqual(id, id.lowercased(), id)
    }
}
