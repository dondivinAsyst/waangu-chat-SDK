import XCTest
import UIKit
@testable import WaanguFeatureChat

final class ChatRoomMediaViewerCoordinatorTests: XCTestCase {

    // MARK: - makeRequest

    func test_makeRequest_startsAtTappedItemIndex() {
        let messages = [
            makeMessage(id: "a", type: .IMAGE),
            makeMessage(id: "b", type: .IMAGE),
            makeMessage(id: "c", type: .IMAGE)
        ]
        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: messages[2],
            in: messages,
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.startIndex, 2)
        XCTAssertEqual(request?.items.map(\.id), ["a", "b", "c"])
    }

    func test_makeRequest_appendsTappedMessageMissingFromTheList() {
        // A just-sent image is not in allMediaMessages yet; it must still open.
        let listed = makeMessage(id: "a", type: .IMAGE)
        let fresh = makeMessage(id: "z", type: .IMAGE)

        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: fresh,
            in: [listed],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.items.map(\.id), ["a", "z"])
        XCTAssertEqual(request?.startIndex, 1)
    }

    func test_makeRequest_videoMessageProducesVideoKind() {
        // Video is a page in the pager now, not a separate sheet.
        let video = makeMessage(id: "v1", type: .VIDEO)
        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: video,
            in: [video],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.items.first?.kind, .video)
    }

    func test_makeRequest_imageMessageProducesImageKind() {
        let image = makeMessage(id: "i1", type: .IMAGE)
        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: image,
            in: [image],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.items.first?.kind, .image)
    }

    func test_makeRequest_dropsNonMediaMessagesFromTheList() {
        let text = makeMessage(id: "t", type: .TEXT)
        let image = makeMessage(id: "i", type: .IMAGE)

        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: image,
            in: [text, image],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.items.map(\.id), ["i"])
        XCTAssertEqual(request?.startIndex, 0)
    }

    func test_makeRequest_deduplicatesRepeatedCodeMessages() {
        let image = makeMessage(id: "i", type: .IMAGE)

        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: image,
            in: [image, image],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.items.map(\.id), ["i"])
    }

    func test_makeRequest_returnsNilForNonMediaTap() {
        let text = makeMessage(id: "t", type: .TEXT)

        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: text,
            in: [],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertNil(request)
    }

    func test_makeRequest_carriesThumbnailFromProvider() {
        let image = makeMessage(id: "i", type: .IMAGE)
        let thumb = UIImage()

        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: image,
            in: [image],
            thumbnailProvider: { $0 == "i" ? thumb : nil }
        )

        XCTAssertTrue(request?.items.first?.thumbnail === thumb)
    }

    func test_makeRequest_carriesCaptionAndSenderMetadata() {
        var image = makeMessage(id: "i", type: .IMAGE)
        image.message.text = "at the beach"

        let request = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: image,
            in: [image],
            thumbnailProvider: { _ in nil }
        )

        XCTAssertEqual(request?.items.first?.caption, "at the beach")
        XCTAssertEqual(request?.items.first?.senderName, "User")
    }

    // MARK: - resolveDocumentURL (unchanged behavior)

    func test_resolveDocumentURL_supportsFilePath() {
        var message = makeMessage(id: "d1", type: .DOCUMENT)
        message.message.file = "/tmp/report.pdf"

        let url = ChatRoomMediaViewerCoordinator.resolveDocumentURL(for: message)
        XCTAssertEqual(url?.path, "/tmp/report.pdf")
    }

    func test_resolveDocumentURL_supportsRemoteURL() {
        var message = makeMessage(id: "d1", type: .DOCUMENT)
        message.message.file = "https://example.com/report.pdf"

        let url = ChatRoomMediaViewerCoordinator.resolveDocumentURL(for: message)
        XCTAssertEqual(url?.absoluteString, "https://example.com/report.pdf")
    }

    // MARK: - Helpers

    private func makeMessage(id: String, type: MessageTypeProps) -> MessageDataItem {
        MessageDataItem(
            codeMessage: id,
            senderId: "sender",
            senderPhone: "111",
            senderName: "User",
            receiverId: "receiver",
            groupId: "",
            typeMessage: type,
            message: MessageContent(text: ""),
            status: .SENT,
            createdAt: Date()
        )
    }
}
