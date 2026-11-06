import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// A live share crosses the same four representations a poll does — domain
/// content, wire JSON, the storage blob, and back — and the share fields are
/// the ones with nowhere to go in the flat shape that predates them. Each hop
/// drops what it does not explicitly carry, so the round trip is what proves
/// a received bubble can still tell it is live.
final class LiveLocationContentCodecTests: XCTestCase {

    private let expiry = Date(timeIntervalSince1970: 1_734_567_890)

    private func liveMessage() -> MessageDataItem {
        var content = MessageContent()
        content.location = ChatLocationItem(
            coords: CoordsLocation(lat: 48.8566, lng: 2.3522),
            title: nil,
            address: nil,
            duration: 900,
            distance: nil,
            isLive: true,
            shareId: "msg-live-001",
            expiresAt: expiry
        )
        return OutgoingMessageBuilder.buildOutgoingMessage(
            content: content,
            type: .LOCATION,
            groupId: nil,
            reply: nil,
            code: "msg-live-001"
        )
    }

    private func pinnedMessage() -> MessageDataItem {
        var content = MessageContent()
        content.location = ChatLocationItem(
            coords: CoordsLocation(lat: 48.8566, lng: 2.3522),
            title: "Louvre",
            address: "Rue de Rivoli",
            duration: nil,
            distance: nil
        )
        return OutgoingMessageBuilder.buildOutgoingMessage(
            content: content,
            type: .LOCATION,
            groupId: nil,
            reply: nil,
            code: "msg-pin-1"
        )
    }

    // MARK: - Outbound

    func test_liveShareWritesTheNestedObject() {
        let dto = MessageContentWireCodec.buildContentDTO(from: liveMessage())

        XCTAssertEqual(dto.location?.isLive, true)
        XCTAssertEqual(dto.location?.shareId, "msg-live-001")
        XCTAssertEqual(dto.location?.latitude, 48.8566)
        XCTAssertEqual(dto.location?.longitude, 2.3522)
        XCTAssertEqual(dto.location?.durationMinutes, 15)
        // Epoch millis on the wire.
        XCTAssertEqual(dto.location?.expiresAt, 1_734_567_890_000)

        // The flat fields stay beside it, so a build that predates live
        // sharing still renders the pin.
        XCTAssertEqual(dto.latitude, 48.8566)
        XCTAssertEqual(dto.longitude, 2.3522)
    }

    /// An ordinary pin must keep exactly the payload it sent before any of this
    /// existed — that is what keeps a stricter server from rejecting sends that
    /// work today.
    func test_pinnedLocationWritesNoNestedObject() {
        let dto = MessageContentWireCodec.buildContentDTO(from: pinnedMessage())

        XCTAssertNil(dto.location)
        XCTAssertEqual(dto.latitude, 48.8566)
        XCTAssertEqual(dto.locationName, "Louvre")
    }

    // MARK: - Round trip

    func test_liveShareSurvivesTheJSONRoundTrip() {
        let encoded = MessageContentWireCodec.encode(from: liveMessage())
        let decoded = MessageContentWireCodec.decode(encoded, typeMessage: "LOCATION")

        XCTAssertEqual(decoded.location?.isLive, true)
        XCTAssertEqual(decoded.location?.shareId, "msg-live-001")

        let content = MessageModelMapper.mapInboundContent(
            decoded,
            type: .location,
            fieldCrypto: LiveLocationPassthroughFieldCrypto()
        )

        XCTAssertEqual(content.isLiveLocation, true)
        XCTAssertEqual(content.liveShareId, "msg-live-001")
        XCTAssertEqual(content.liveExpiresAt, expiry.timeIntervalSince1970)
        XCTAssertEqual(content.latitude, 48.8566)
    }

    // MARK: - Inbound

    /// The shape the integration note documents, straight off another client.
    func test_readsNestedShareFieldsFromTheWire() {
        let json = """
        {"location":{"latitude":48.857,"longitude":2.353,"isLive":true,\
        "shareId":"msg-live-002","expiresAt":1734567890000,"durationMinutes":30}}
        """
        let dto = MessageContentWireCodec.decode(json, typeMessage: "LOCATION")
        let content = MessageModelMapper.mapInboundContent(
            dto,
            type: .location,
            fieldCrypto: LiveLocationPassthroughFieldCrypto()
        )

        XCTAssertEqual(content.latitude, 48.857)
        XCTAssertEqual(content.longitude, 2.353)
        XCTAssertEqual(content.isLiveLocation, true)
        XCTAssertEqual(content.liveShareId, "msg-live-002")
        XCTAssertEqual(content.liveDurationSeconds, 1800)
        XCTAssertEqual(content.liveExpiresAt, 1_734_567_890)
    }

    /// Quoted numbers and a quoted flag, which other platforms on this wire do
    /// send — repaired rather than taking the whole content object down.
    func test_repairsQuotedShareFields() {
        let json = """
        {"location":{"latitude":"48.857","longitude":"2.353","isLive":"true",\
        "shareId":"msg-live-003","expiresAt":"1734567890000"}}
        """
        let dto = MessageContentWireCodec.decode(json, typeMessage: "LOCATION")

        XCTAssertEqual(dto.location?.latitude, 48.857)
        XCTAssertEqual(dto.location?.isLive, true)
        XCTAssertEqual(dto.location?.expiresAt, 1_734_567_890_000)
    }

    /// A sender that predates the nested object still lands a readable pin.
    func test_flatOnlyPayloadStillMaps() {
        let json = """
        {"latitude":48.857,"longitude":2.353,"locationName":"Louvre"}
        """
        let dto = MessageContentWireCodec.decode(json, typeMessage: "LOCATION")
        let content = MessageModelMapper.mapInboundContent(
            dto,
            type: .location,
            fieldCrypto: LiveLocationPassthroughFieldCrypto()
        )

        XCTAssertEqual(content.latitude, 48.857)
        XCTAssertEqual(content.locationName, "Louvre")
        XCTAssertNil(content.isLiveLocation)
    }
    // MARK: - Ended state

    /// The contract has no unbounded share — every start carries `expiresAt` —
    /// so an anchor without one is a share whose end was never recorded, not a
    /// share that runs forever. Reading it as live is what made every such
    /// bubble come back live on relaunch, with no countdown to contradict it.
    func test_shareWithoutADeadlineReadsAsEnded() {
        let location = ChatLocationItem(
            coords: CoordsLocation(lat: 48.8566, lng: 2.3522),
            title: nil,
            address: nil,
            duration: nil,
            distance: nil,
            isLive: true,
            shareId: "msg-live-001",
            expiresAt: nil
        )

        XCTAssertFalse(location.isLiveActive())
    }

    func test_theDeadlineDecidesWhetherAShareIsRunning() {
        let now = Date()
        func share(expiringIn seconds: TimeInterval) -> ChatLocationItem {
            ChatLocationItem(
                coords: CoordsLocation(lat: 1, lng: 2),
                title: nil,
                address: nil,
                duration: nil,
                distance: nil,
                isLive: true,
                shareId: "s",
                expiresAt: now.addingTimeInterval(seconds)
            )
        }

        XCTAssertTrue(share(expiringIn: 60).isLiveActive(asOf: now))
        XCTAssertFalse(share(expiringIn: -1).isLiveActive(asOf: now))
    }

    /// A sender that gave a duration but no deadline still gets a live bubble:
    /// the send time plus the duration says the same thing, and is the only
    /// other record of how long the share was meant to run.
    func test_storedShareWithoutDeadlineDerivesOneFromItsDuration() {
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)
        let model = MessageModel(
            id: "msg-live-004",
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .location,
            content: MessageContentModel(
                latitude: 48.857,
                longitude: 2.353,
                liveDurationSeconds: 900,
                isLiveLocation: true,
                liveShareId: "msg-live-004"
            ),
            timestamp: sentAt
        )

        let item = MessageModelMapper.toDomain(model, fieldCrypto: LiveLocationPassthroughFieldCrypto())

        XCTAssertEqual(item.message.location?.expiresAt, sentAt.addingTimeInterval(900))
        XCTAssertTrue(
            item.message.location?.isLiveActive(asOf: sentAt.addingTimeInterval(600)) == true
        )
        XCTAssertFalse(
            item.message.location?.isLiveActive(asOf: sentAt.addingTimeInterval(1200)) == true
        )
    }

    /// An ordinary pin has no duration to derive from and must stay a pin.
    func test_pinnedLocationGainsNoDeadline() {
        let model = MessageModel(
            id: "msg-pin-2",
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .location,
            content: MessageContentModel(latitude: 48.857, longitude: 2.353)
        )

        let item = MessageModelMapper.toDomain(model, fieldCrypto: LiveLocationPassthroughFieldCrypto())

        XCTAssertNil(item.message.location?.expiresAt)
        XCTAssertNil(item.message.location?.isLive)
        XCTAssertFalse(item.message.location?.isLiveActive() == true)
    }
}

/// `private` to this file, as every other codec test declares its own.
private struct LiveLocationPassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
