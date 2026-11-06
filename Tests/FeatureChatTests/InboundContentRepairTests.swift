import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// An image sent from Android arrived in the room with no picture, no thumbnail
/// and no size, while the payload on the wire looked perfectly well formed.
///
/// The cause was one quoted number: `"width":"1280"` against a declared `Int?`.
/// `JSONDecoder` does no string→number conversion, so the whole content object
/// failed to decode, and because `MessageContentWireCodec.decode` swallows that
/// with `try?` the plain-text fallback then handed `url` the entire JSON blob.
/// Nothing logged, and every field the bubble needed was nil.
///
/// These tests pin both halves: the tolerant read, and — just as important — the
/// fact that the payloads which already worked still decode exactly as before.
final class InboundContentRepairTests: XCTestCase {

    /// The real payload, base64 thumbnail truncated. Note `size` rather than
    /// `fileSize`, and `width`/`height` as strings.
    private let androidImageContent = """
    {"url":"http://192.168.30.43:9000/waangu-chat-media/default/message/WAANGU_1786974925909.jpg",\
    "mimeType":"image/jpeg","fileName":"46","size":547406,"width":"1280","height":"960",\
    "thumbnailURL":"data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA=="}
    """

    // MARK: - The reported bug

    func test_androidImageContentDecodesEveryMediaField() {
        let dto = MessageContentWireCodec.decode(androidImageContent, typeMessage: "IMAGE")

        XCTAssertEqual(
            dto.url,
            "http://192.168.30.43:9000/waangu-chat-media/default/message/WAANGU_1786974925909.jpg"
        )
        XCTAssertEqual(dto.mimeType, "image/jpeg")
        XCTAssertEqual(dto.fileName, "46")
        XCTAssertEqual(dto.fileSize, 547_406)
        XCTAssertEqual(dto.width, 1280)
        XCTAssertEqual(dto.height, 960)
        XCTAssertEqual(
            dto.thumbnailURL,
            "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA=="
        )
    }

    /// The specific failure the user saw: `url` holding the content JSON itself.
    func test_repairedContentNeverPutsTheJSONBlobInURL() {
        let dto = MessageContentWireCodec.decode(androidImageContent, typeMessage: "IMAGE")

        XCTAssertFalse(dto.url?.hasPrefix("{") ?? false)
        XCTAssertNil(dto.text)
    }

    /// The same payload through the envelope the MQTT handler actually receives.
    func test_androidImageSurvivesTheInboundEnvelope() {
        let dto = InboundMessageDTO(
            senderId: "110691817141112601",
            senderName: "JAKIN IRISA",
            senderPhone: "098741201",
            senderAvatar: "",
            receiverId: "611768bb8b70e0c342bedd7b",
            conversationId: "f3c02768-b6e0-3087-a9ee-cbda6975873a",
            codeMessage: "484d3205-6f7d-4553-b960-c73e2cc255fc",
            content: androidImageContent,
            typeMessage: "IMAGE",
            status: "SEEN",
            forwarded: false,
            viewOnce: false,
            isMoney: false,
            isMessageSystem: false
        )

        let content = MessageModelMapper.mapInboundContent(
            dto.messageContent,
            type: .image,
            fieldCrypto: RepairPassthroughFieldCrypto()
        )

        XCTAssertEqual(content.fileSize, 547_406)
        XCTAssertEqual(content.width, 1280)
        XCTAssertEqual(content.height, 960)
        XCTAssertEqual(content.mimeType, "image/jpeg")
        XCTAssertNotNil(content.thumbnailURL)
        XCTAssertTrue(content.url?.hasPrefix("http://") ?? false)
    }

    // MARK: - fileSize keeps its name

    /// `size` is read *into* `fileSize`. The property, the storage column and
    /// every outbound payload keep the one name they always had.
    func test_outboundStillSpellsItFileSize() {
        let message = OutgoingMessageBuilder.buildOutgoingMessage(
            content: MessageContent(
                text: "",
                image: "https://cdn.example.com/photo.jpg",
                fileName: "photo.jpg",
                size: 547_406,
                width: 1280,
                height: 960,
                mimeType: "image/jpeg"
            ),
            type: .IMAGE,
            groupId: nil,
            reply: nil,
            code: "img-1"
        )

        let encoded = MessageContentWireCodec.encode(from: message)

        XCTAssertTrue(encoded.contains("\"fileSize\":547406"))
        XCTAssertFalse(encoded.contains("\"size\":"))
        XCTAssertEqual(MessageContentWireCodec.decode(encoded, typeMessage: "IMAGE").fileSize, 547_406)
    }

    /// An explicit `fileSize` is never overwritten by an alias sitting alongside it.
    func test_explicitFileSizeWinsOverAlias() {
        let dto = MessageContentWireCodec.decode(
            #"{"url":"https://x/y.jpg","fileSize":111,"size":222,"width":"10"}"#,
            typeMessage: "IMAGE"
        )

        XCTAssertEqual(dto.fileSize, 111)
    }

    // MARK: - Nothing that worked stops working

    /// A well-formed payload must not go anywhere near the repair pass.
    func test_wellFormedNumbersDecodeUnchanged() {
        let dto = MessageContentWireCodec.decode(
            #"{"url":"https://x/y.jpg","fileSize":547406,"width":1280,"height":960,"text":"hi"}"#,
            typeMessage: "IMAGE"
        )

        XCTAssertEqual(dto.fileSize, 547_406)
        XCTAssertEqual(dto.width, 1280)
        XCTAssertEqual(dto.height, 960)
        XCTAssertEqual(dto.text, "hi")
    }

    /// Legacy senders put a bare URL in `content`, not JSON. Still a media URL.
    func test_legacyPlainURLContentStillFallsBack() {
        let dto = MessageContentWireCodec.decode("https://x/y.jpg", typeMessage: "IMAGE")

        XCTAssertEqual(dto.url, "https://x/y.jpg")
        XCTAssertNil(dto.text)
    }

    func test_legacyPlainTextContentStillFallsBack() {
        let dto = MessageContentWireCodec.decode("hello there", typeMessage: "TEXT")

        XCTAssertEqual(dto.text, "hello there")
        XCTAssertNil(dto.url)
    }

    /// Repair is a retry, not a rescue: content that is not a JSON object at all
    /// lands on the same fallback it always did.
    func test_undecodableContentStillFallsBack() {
        let dto = MessageContentWireCodec.decode("[1,2,3]", typeMessage: "TEXT")

        XCTAssertEqual(dto.text, "[1,2,3]")
    }

    // MARK: - The rest of the coercions

    func test_quotedDoublesAndBoolsAreCoerced() {
        let dto = MessageContentWireCodec.decode(
            #"{"latitude":"4.05","longitude":"9.7","locationName":"Douala","liveDurationSeconds":"60"}"#,
            typeMessage: "LOCATION"
        )

        XCTAssertEqual(dto.latitude, 4.05)
        XCTAssertEqual(dto.longitude, 9.7)
        XCTAssertEqual(dto.locationName, "Douala")
        XCTAssertEqual(dto.liveDurationSeconds, 60)
    }

    func test_quotedBoolIsCoerced() {
        let dto = MessageContentWireCodec.decode(
            #"{"contactName":"Ada","contactPhone":"+237","isRegistered":"true","width":"10"}"#,
            typeMessage: "CONTACT"
        )

        XCTAssertEqual(dto.isRegistered, true)
        XCTAssertEqual(dto.contactName, "Ada")
    }

    /// Nested objects are repaired on the same pass, so a quoted `voteCount`
    /// inside `pollOptions` survives too.
    func test_nestedPollOptionNumbersAreCoerced() {
        let dto = MessageContentWireCodec.decode(
            """
            {"pollQuestion":"Lunch?","pollIsClosed":"false","pollOptions":[\
            {"id":"a","text":"Pizza","voteCount":"3"},{"id":"b","text":"Sushi","voteCount":0}]}
            """,
            typeMessage: "POLL"
        )

        XCTAssertEqual(dto.pollQuestion, "Lunch?")
        XCTAssertEqual(dto.pollIsClosed, false)
        XCTAssertEqual(dto.pollOptions?.first?.voteCount, 3)
        XCTAssertEqual(dto.pollOptions?.last?.voteCount, 0)
    }

    /// A string that is not a number is left alone rather than zeroed — the field
    /// stays nil and the fallback decides, which is honest about knowing nothing.
    func test_nonNumericStringIsNotInvented() {
        let dto = MessageContentWireCodec.decode(
            #"{"url":"https://x/y.jpg","width":"wide","fileSize":"547406"}"#,
            typeMessage: "IMAGE"
        )

        XCTAssertNil(dto.width)
        XCTAssertEqual(dto.url, "https://x/y.jpg")
        XCTAssertEqual(dto.fileSize, 547_406)
    }

    /// A quoted decimal lands in whichever numeric type the field declares —
    /// `1280.0` must reach an `Int` field as an integer, not as a decode failure.
    func test_quotedDecimalsLandInTheDeclaredNumericType() {
        let dto = MessageContentWireCodec.decode(
            #"{"url":"https://x/y.jpg","width":"1280.0","durationSeconds":"12.5"}"#,
            typeMessage: "VIDEO"
        )

        XCTAssertEqual(dto.width, 1280)
        XCTAssertEqual(dto.durationSeconds, 12.5)
    }

    func test_nullFileSizeAliasIsIgnored() {
        let dto = MessageContentWireCodec.decode(
            #"{"url":"https://x/y.jpg","size":null,"width":"10"}"#,
            typeMessage: "IMAGE"
        )

        XCTAssertNil(dto.fileSize)
        XCTAssertEqual(dto.width, 10)
    }
}

private struct RepairPassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
