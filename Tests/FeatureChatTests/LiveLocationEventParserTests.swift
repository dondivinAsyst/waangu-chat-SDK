import XCTest
@testable import WaanguFeatureChat

/// Live location ticks reach the app on the same user inbox as messages and are
/// distinguished only by `eventType`. Before this existed they fell through the
/// parser's `default` and vanished, so these cover the two shapes seen on the
/// wire and the cases that must still be dropped.
final class LiveLocationEventParserTests: XCTestCase {

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Update

    func test_parsesDocumentedUpdateShape() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_UPDATE",
            "conversationId": "conv-uuid",
            "suppressNotification": true,
            "payload": [
                "eventType": "LIVE_LOCATION_UPDATE",
                "shareId": "msg-live-001",
                "codeMessage": "msg-live-001",
                "conversationId": "conv-uuid",
                "senderId": "user-A",
                "location": ["latitude": 48.857, "longitude": 2.353, "accuracy": 12],
                "expiresAt": 1_734_567_890_000,
                "timestamp": "2026-08-20T07:45:00.000Z"
            ]
        ]))

        XCTAssertEqual(event?.type, "live_location_update")
        XCTAssertEqual(event?.referenceId, "msg-live-001")
        XCTAssertEqual(event?.conversationId, "conv-uuid")

        let dto = event?.decodePayload(as: InboundLiveLocationDTO.self)
        XCTAssertEqual(dto?.shareId, "msg-live-001")
        XCTAssertEqual(dto?.senderId, "user-A")
        XCTAssertEqual(dto?.location?.latitude, 48.857)
        XCTAssertEqual(dto?.location?.longitude, 2.353)
        XCTAssertEqual(dto?.location?.accuracy, 12)
        // Millis on the wire, seconds in the DTO.
        XCTAssertEqual(dto?.expiresAt, 1_734_567_890)
    }

    /// The ingress tick shape, in case a tick is fanned out as it arrived.
    func test_acceptsFlatCoordinateKeys() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_UPDATE",
            "payload": [
                "shareId": "msg-live-002",
                "userId": "user-A",
                "lat": 48.857,
                "lng": 2.353,
                "accuracy": 12,
                "timestamp": 1_734_567_800_000
            ]
        ]))

        let dto = event?.decodePayload(as: InboundLiveLocationDTO.self)
        XCTAssertEqual(event?.type, "live_location_update")
        XCTAssertEqual(dto?.location?.latitude, 48.857)
        XCTAssertEqual(dto?.location?.longitude, 2.353)
        // `userId` is the owner of the share on the ingress shape.
        XCTAssertEqual(dto?.senderId, "user-A")
        XCTAssertEqual(event?.at, 1_734_567_800)
    }

    func test_acceptsQuotedNumbers() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_UPDATE",
            "payload": [
                "shareId": "msg-live-003",
                "location": ["latitude": "48.857", "longitude": "2.353"],
                "expiresAt": "1734567890000"
            ]
        ]))

        let dto = event?.decodePayload(as: InboundLiveLocationDTO.self)
        XCTAssertEqual(dto?.location?.latitude, 48.857)
        XCTAssertEqual(dto?.location?.longitude, 2.353)
        XCTAssertEqual(dto?.expiresAt, 1_734_567_890)
    }

    func test_fallsBackToCodeMessageAsShareId() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_UPDATE",
            "payload": [
                "codeMessage": "msg-live-004",
                "location": ["latitude": 1.0, "longitude": 2.0]
            ]
        ]))

        XCTAssertEqual(event?.referenceId, "msg-live-004")
        XCTAssertEqual(event?.decodePayload(as: InboundLiveLocationDTO.self)?.shareId, "msg-live-004")
    }

    /// Nothing to move the pin to, and nothing to persist either.
    func test_dropsUpdateWithoutPosition() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_UPDATE",
            "payload": ["shareId": "msg-live-005"]
        ]))

        XCTAssertNil(event)
    }

    func test_dropsEventWithoutShareId() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_UPDATE",
            "payload": ["location": ["latitude": 1.0, "longitude": 2.0]]
        ]))

        XCTAssertNil(event)
    }

    // MARK: - Stop

    func test_parsesStopWithFinalPosition() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_STOP",
            "payload": [
                "shareId": "msg-live-006",
                "conversationId": "conv-uuid",
                "location": ["latitude": 48.857, "longitude": 2.353]
            ]
        ]))

        XCTAssertEqual(event?.type, "live_location_stop")
        XCTAssertEqual(event?.referenceId, "msg-live-006")
        XCTAssertEqual(event?.decodePayload(as: InboundLiveLocationDTO.self)?.location?.latitude, 48.857)
    }

    /// A bare stop still has to arrive: it ends the share, and the pin the
    /// receiver already holds stays where it was.
    func test_parsesStopWithoutPosition() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_STOP",
            "payload": ["shareId": "msg-live-007"]
        ]))

        XCTAssertEqual(event?.type, "live_location_stop")
        XCTAssertEqual(event?.referenceId, "msg-live-007")
        XCTAssertNil(event?.decodePayload(as: InboundLiveLocationDTO.self)?.location)
    }
}
