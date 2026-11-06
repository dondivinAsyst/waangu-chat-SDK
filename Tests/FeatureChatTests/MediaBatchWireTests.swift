import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Several photos sent at once are one group on the sender's screen and were a
/// pile of separate rows on the receiver's.
///
/// `mediaBatchId` existed in the domain content and in the storage row, so the
/// sender read back its own batch and grouped it. The wire DTO never declared
/// the field and the inbound mapper hardcoded it to nil, so it reached nobody
/// else. These tests pin the field to the wire in both directions.
final class MediaBatchWireTests: XCTestCase {

    private func imageMessage(batchId: String?) -> MessageDataItem {
        OutgoingMessageBuilder.buildOutgoingMessage(
            content: MessageContent(
                text: "",
                image: "https://cdn.example.com/photo.jpg",
                fileName: "photo.jpg",
                size: 1024,
                mimeType: "image/jpeg",
                mediaBatchId: batchId
            ),
            type: .IMAGE,
            groupId: nil,
            reply: nil,
            code: "img-1"
        )
    }

    // MARK: - Outbound

    func test_batchIdIsSentOnTheWire() {
        let encoded = MessageContentWireCodec.encode(from: imageMessage(batchId: "batch-7"))

        XCTAssertTrue(encoded.contains("\"mediaBatchId\":\"batch-7\""))
        XCTAssertEqual(
            MessageContentWireCodec.decode(encoded, typeMessage: "IMAGE").mediaBatchId,
            "batch-7"
        )
    }

    /// A single send carries no batch, and must not start sending an empty key.
    func test_singleSendOmitsTheBatchId() {
        let encoded = MessageContentWireCodec.encode(from: imageMessage(batchId: nil))

        XCTAssertFalse(encoded.contains("mediaBatchId"))
        XCTAssertNil(MessageContentWireCodec.decode(encoded, typeMessage: "IMAGE").mediaBatchId)
    }

    func test_emptyBatchIdIsTreatedAsNoBatch() {
        let encoded = MessageContentWireCodec.encode(from: imageMessage(batchId: ""))

        XCTAssertFalse(encoded.contains("mediaBatchId"))
    }

    // MARK: - Inbound

    func test_receivedBatchIdReachesTheDomainContent() {
        let dto = InboundMessageDTO(
            senderId: "u1",
            senderName: "Ada",
            conversationId: "c1",
            codeMessage: "img-1",
            content: #"{"url":"https://x/1.jpg","mimeType":"image/jpeg","mediaBatchId":"batch-7"}"#,
            typeMessage: "IMAGE"
        )

        guard let model = MessageModelMapper.toModel(
            from: dto,
            fieldCrypto: BatchPassthroughFieldCrypto()
        ) else {
            return XCTFail("Inbound image failed to map to a model")
        }

        XCTAssertEqual(model.content.mediaBatchId, "batch-7")

        let item = MessageModelMapper.toDomain(model, fieldCrypto: BatchPassthroughFieldCrypto())
        XCTAssertEqual(item.message.mediaBatchId, "batch-7")
    }

    /// Two photos of one send agree on the batch, which is the whole basis the
    /// timeline groups on.
    func test_aBatchArrivesAsOneBatch() {
        let ids = ["1", "2"].map { index -> String? in
            let dto = InboundMessageDTO(
                senderId: "u1",
                senderName: "Ada",
                conversationId: "c1",
                codeMessage: "img-\(index)",
                content: #"{"url":"https://x/\#(index).jpg","mediaBatchId":"batch-7"}"#,
                typeMessage: "IMAGE"
            )
            return MessageModelMapper.toModel(
                from: dto,
                fieldCrypto: BatchPassthroughFieldCrypto()
            )?.content.mediaBatchId
        }

        XCTAssertEqual(ids, ["batch-7", "batch-7"])
    }

    func test_messageWithNoBatchIdStaysUngrouped() {
        let dto = InboundMessageDTO(
            senderId: "u1",
            senderName: "Ada",
            conversationId: "c1",
            codeMessage: "img-1",
            content: #"{"url":"https://x/1.jpg","mimeType":"image/jpeg"}"#,
            typeMessage: "IMAGE"
        )

        let model = MessageModelMapper.toModel(from: dto, fieldCrypto: BatchPassthroughFieldCrypto())

        XCTAssertNil(model?.content.mediaBatchId)
    }

    /// An empty string would bucket every unbatched photo together under one
    /// blank key, so it has to read as no batch at all.
    func test_emptyInboundBatchIdReadsAsNoBatch() {
        let dto = InboundMessageDTO(
            senderId: "u1",
            senderName: "Ada",
            conversationId: "c1",
            codeMessage: "img-1",
            content: #"{"url":"https://x/1.jpg","mediaBatchId":""}"#,
            typeMessage: "IMAGE"
        )

        let model = MessageModelMapper.toModel(from: dto, fieldCrypto: BatchPassthroughFieldCrypto())

        XCTAssertNil(model?.content.mediaBatchId)
    }

    // MARK: - Round trip

    /// What this device sends, this device can read back — the case that matters
    /// for iOS→iOS grouping.
    func test_batchSurvivesTheFullRoundTrip() {
        let encoded = MessageContentWireCodec.encode(from: imageMessage(batchId: "batch-7"))
        let dto = InboundMessageDTO(
            senderId: "u1",
            senderName: "Ada",
            conversationId: "c1",
            codeMessage: "img-1",
            content: encoded,
            typeMessage: "IMAGE"
        )

        guard let model = MessageModelMapper.toModel(
            from: dto,
            fieldCrypto: BatchPassthroughFieldCrypto()
        ) else {
            return XCTFail("Round-tripped image failed to map to a model")
        }

        XCTAssertEqual(
            MessageModelMapper.toDomain(model, fieldCrypto: BatchPassthroughFieldCrypto())
                .message.mediaBatchId,
            "batch-7"
        )
    }
}

private struct BatchPassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
