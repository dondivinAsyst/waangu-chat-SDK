import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// A video note is a video with its own type. Every hop that does not name
/// `VIDEO_NOTE` falls back to text, which loses the media URL without an error,
/// so each hop is checked on its own.
final class VideoNoteTypeTests: XCTestCase {

    private let videoURL = "https://cdn.invalid/note.mp4"

    // MARK: - Type mapping

    func test_inboundVideoNoteTypeMapsToVideoNote() {
        XCTAssertEqual(MessageModelMapper.mapInboundType("VIDEO_NOTE"), .videoNote)
        XCTAssertEqual(MessageModelMapper.mapInboundType("video_note"), .videoNote)
    }

    func test_videoNoteRoundTripsBetweenDomainAndStorage() {
        XCTAssertEqual(MessageModelMapper.mapType(.VIDEO_NOTE), .videoNote)
        XCTAssertEqual(MessageModelMapper.mapMessageType(.videoNote), .VIDEO_NOTE)
    }

    func test_videoNoteWireNameIsVIDEO_NOTE() {
        XCTAssertEqual(MessageTypeProps.VIDEO_NOTE.rawValue, "VIDEO_NOTE")
    }

    func test_isVideoCoversVideoAndVideoNoteOnly() {
        XCTAssertTrue(MessageTypeProps.VIDEO.isVideo)
        XCTAssertTrue(MessageTypeProps.VIDEO_NOTE.isVideo)
        XCTAssertFalse(MessageTypeProps.IMAGE.isVideo)
        XCTAssertFalse(MessageTypeProps.CALL_VIDEO.isVideo)
    }

    // MARK: - Storage to domain

    func test_storedVideoNoteCarriesItsURLAsVideo() {
        let model = MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                                 type: .videoNote,
                                 content: MessageContentModel(url: videoURL))

        let item = MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto())

        XCTAssertEqual(item.typeMessage, .VIDEO_NOTE)
        XCTAssertEqual(item.message.video, videoURL)
        XCTAssertNil(item.message.image)
        XCTAssertNil(item.message.audio)
    }

    func test_quotedVideoNoteKeepsItsThumbnail() {
        let model = MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                                 content: .text("nice"),
                                 replyToMessageId: "orig", replyToSenderName: "Aline",
                                 replyToMessageType: .videoNote,
                                 replyToThumbnailURL: "https://cdn.invalid/thumb.jpg")

        let item = MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto())

        guard case .message(let quoted?) = item.reply else { return XCTFail("reply expected") }
        XCTAssertEqual(quoted.typeMessage, .VIDEO_NOTE)
        XCTAssertEqual(quoted.message.video, "https://cdn.invalid/thumb.jpg")
        XCTAssertEqual(quoted.message.thumbnail, "https://cdn.invalid/thumb.jpg")
    }

    // MARK: - Previews

    func test_conversationPreviewNamesTheVideoNote() {
        let item = MessageModelMapper.toDomain(
            MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                         type: .videoNote,
                         content: MessageContentModel(url: videoURL)),
            fieldCrypto: PassthroughFieldCrypto()
        )

        XCTAssertEqual(MessageModelMapper.buildLastMessagePreview(item), "🎥 Video note")
    }
}

private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
