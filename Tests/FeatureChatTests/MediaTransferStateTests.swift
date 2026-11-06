import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Media that failed to send was indistinguishable from media still queued.
///
/// `shouldRetry` was the flag six bubbles branched on, and nothing ever set it
/// true — every write in the codebase said `false`, and the storage mapper
/// hardcoded `shouldRetry: false` on the way back out. Failure lived only in
/// `FileUploadViewModel.uploads`, which is memory, so it did not survive leaving
/// the room.
final class MediaTransferStateTests: XCTestCase {

    private func sentImage(
        pending: Bool,
        failed: Bool,
        code: String = "img-1"
    ) -> MessageDataItem {
        var content = MessageContent(
            text: "",
            image: "https://cdn.example.com/photo.jpg",
            shouldUploadDownload: pending,
            shouldRetry: failed,
            fileName: "photo.jpg",
            size: 1024,
            mimeType: "image/jpeg"
        )
        content.remoteUri = "https://cdn.example.com/photo.jpg"
        return OutgoingMessageBuilder.buildOutgoingMessage(
            content: content,
            type: .IMAGE,
            groupId: nil,
            reply: nil,
            code: code
        )
    }

    /// The resolver serves the voice and document bubbles; the flag logic it turns
    /// on is the same one the media button reads.
    private func sentDocument(pending: Bool, failed: Bool) -> MessageDataItem {
        var content = MessageContent(
            text: "",
            shouldUploadDownload: pending,
            shouldRetry: failed,
            file: "https://cdn.example.com/report.pdf",
            fileName: "report.pdf",
            size: 2048,
            mimeType: "application/pdf"
        )
        content.remoteUri = "https://cdn.example.com/report.pdf"
        return OutgoingMessageBuilder.buildOutgoingMessage(
            content: content,
            type: .DOCUMENT,
            groupId: nil,
            reply: nil,
            code: "doc-1"
        )
    }

    // MARK: - Persistence

    func test_failureSurvivesTheStorageRoundTrip() {
        let stored = MessageModelMapper.buildContent(
            from: sentImage(pending: true, failed: true),
            fieldCrypto: TransferPassthroughFieldCrypto()
        )

        XCTAssertEqual(stored.mediaTransferFailed, true)

        let model = MessageModel(
            id: "img-1",
            conversationId: "c1",
            senderId: CurrentSessionInfo.shared.currentUid,
            senderName: "Ada",
            type: .image,
            content: stored
        )
        let item = MessageModelMapper.toDomain(model, fieldCrypto: TransferPassthroughFieldCrypto())

        XCTAssertTrue(item.message.shouldRetry)
        XCTAssertTrue(item.message.shouldUploadDownload)
    }

    /// A message that never failed must not start claiming it did.
    func test_healthyMediaStoresNoFailure() {
        let stored = MessageModelMapper.buildContent(
            from: sentImage(pending: true, failed: false),
            fieldCrypto: TransferPassthroughFieldCrypto()
        )

        XCTAssertNil(stored.mediaTransferFailed)

        let model = MessageModel(
            id: "img-1",
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .image,
            content: stored
        )

        XCTAssertFalse(
            MessageModelMapper.toDomain(model, fieldCrypto: TransferPassthroughFieldCrypto())
                .message.shouldRetry
        )
    }

    /// Transfer state is local. A message straight off the wire has attempted
    /// nothing, whatever any sender claims.
    func test_inboundMessageCarriesNoFailure() {
        let dto = InboundMessageDTO(
            senderId: "u1",
            senderName: "Ada",
            conversationId: "c1",
            codeMessage: "img-1",
            content: #"{"url":"https://x/1.jpg","mediaTransferFailed":true}"#,
            typeMessage: "IMAGE"
        )

        let model = MessageModelMapper.toModel(
            from: dto,
            fieldCrypto: TransferPassthroughFieldCrypto()
        )

        XCTAssertNil(model?.content.mediaTransferFailed)
    }

    // MARK: - Resolver

    /// The case that made this bug visible: a failed upload is *both* pending and
    /// failed. The resolver used to test the two flags as mutually exclusive, so
    /// this combination matched neither branch and fell through to `.ready` — no
    /// control at all on the one message that needs one.
    func test_failedUploadIsFailedNotReady() {
        let phase = InlineMediaTransferStateResolver.phase(
            config: .document(message: sentDocument(pending: true, failed: true), localFileURL: nil),
            uploadState: nil,
            downloadState: nil
        )

        XCTAssertEqual(phase, .failed)
    }

    func test_pendingUploadWithNoLiveStateIsIdle() {
        let phase = InlineMediaTransferStateResolver.phase(
            config: .document(message: sentDocument(pending: true, failed: false), localFileURL: nil),
            uploadState: nil,
            downloadState: nil
        )

        XCTAssertEqual(phase, .idle)
    }

    /// Nothing pending and the file already here — there is no work left.
    ///
    /// `localFileURL` is what carries "here": once `isUpload` became "still owes
    /// the server", a settled message takes the download branch, and that branch
    /// asks the file system rather than the flags.
    func test_settledMediaWithItsFileIsReady() {
        let phase = InlineMediaTransferStateResolver.phase(
            config: .document(
                message: sentDocument(pending: false, failed: false),
                localFileURL: URL(fileURLWithPath: "/tmp/report.pdf")
            ),
            uploadState: nil,
            downloadState: nil
        )

        XCTAssertEqual(phase, .ready)
    }

    /// Settled, but the file is not on this device — it has to come down. This is
    /// the multi-device case, and it is why the branch reads the disk.
    func test_settledMediaWithoutItsFileNeedsFetching() {
        let phase = InlineMediaTransferStateResolver.phase(
            config: .document(message: sentDocument(pending: false, failed: false), localFileURL: nil),
            uploadState: nil,
            downloadState: nil
        )

        XCTAssertEqual(phase, .idle)
    }

    /// What is happening now outranks what was recorded about the last attempt —
    /// a retry in flight must not still read as failed.
    func test_liveProgressOutranksStoredFailure() {
        let phase = InlineMediaTransferStateResolver.phase(
            config: .document(message: sentDocument(pending: true, failed: true), localFileURL: nil),
            uploadState: .uploading(progress: 0.4),
            downloadState: nil
        )

        XCTAssertEqual(phase, .transferring(progress: 0.4))
    }

    func test_liveSuccessOutranksStoredFailure() {
        let phase = InlineMediaTransferStateResolver.phase(
            config: .document(message: sentDocument(pending: true, failed: true), localFileURL: nil),
            uploadState: .success(url: "https://cdn.example.com/photo.jpg"),
            downloadState: nil
        )

        XCTAssertEqual(phase, .ready)
    }

    // MARK: - Same account, another device

    /// Media sent from the web or a second phone arrives with our own `senderId`,
    /// so `direction == .sent`. Every transfer decision used to read direction, so
    /// such a message reported nothing left to do: no download control, and a bare
    /// thumbnail with no way to get the real file.
    private func sentFromAnotherDevice() -> MessageDataItem {
        var content = MessageContent(
            text: "",
            image: "https://cdn.example.com/from-web.jpg",
            // Neither flag is set: this device never queued it and never failed it.
            shouldUploadDownload: false,
            shouldRetry: false,
            fileName: "from-web.jpg",
            size: 4096,
            mimeType: "image/jpeg"
        )
        content.remoteUri = "https://cdn.example.com/from-web.jpg"

        // Built by hand rather than through `buildOutgoingMessage` so the code is a
        // server id this device has never held a file for.
        return MessageDataItem(
            codeMessage: "from-web-\(UUID().uuidString)",
            senderId: CurrentSessionInfo.shared.currentUid,
            senderPhone: "",
            senderName: "Me",
            receiverId: "u2",
            typeMessage: .IMAGE,
            message: content,
            status: .SENT,
            isMoney: false,
            createdAt: Date()
        )
    }

    func test_ourOwnMediaFromAnotherDeviceStillNeedsFetching() {
        let message = sentFromAnotherDevice()

        // It reads as ours — that part was never wrong.
        XCTAssertEqual(message.direction, .sent)
        // But this device does not have the file, so there is work to do.
        XCTAssertTrue(message.mediaNeedsTransfer)
    }

    func test_ourOwnMediaFromAnotherDeviceIsADownload() {
        XCTAssertTrue(sentFromAnotherDevice().mediaTransferIsDownload)
    }

    /// Media this device is still sending is the only case that uploads.
    func test_mediaThisDevicePendingIsAnUpload() {
        XCTAssertFalse(sentImage(pending: true, failed: false).mediaTransferIsDownload)
    }

    func test_failedUploadIsStillAnUpload() {
        XCTAssertFalse(sentImage(pending: true, failed: true).mediaTransferIsDownload)
    }

    // MARK: - Remote address

    func test_remoteURLIsUsedForMediaFromAnotherDevice() {
        XCTAssertEqual(
            sentFromAnotherDevice().remoteMediaURLString,
            "https://cdn.example.com/from-web.jpg"
        )
    }

    /// The case the old `image ?? remoteUri` precedence got wrong: a message this
    /// device queued holds a filesystem path in `image`, and handing that to a
    /// downloader fails looking exactly like a network error.
    func test_aLocalPathIsNeverOfferedAsARemoteURL() {
        var content = MessageContent(
            text: "",
            image: "/var/mobile/Containers/Data/Application/ABC/tmp/IMG_0042.jpg",
            shouldUploadDownload: false,
            shouldRetry: false,
            fileName: "IMG_0042.jpg",
            size: 1024,
            mimeType: "image/jpeg"
        )
        content.remoteUri = nil

        let message = MessageDataItem(
            codeMessage: "local-only",
            senderId: CurrentSessionInfo.shared.currentUid,
            typeMessage: .IMAGE,
            message: content,
            createdAt: Date()
        )

        XCTAssertNil(message.remoteMediaURLString)
    }

    /// Media that is not here still offers a control even when no address can be
    /// resolved. An attempt that fails is visible and retryable; showing nothing
    /// leaves the user with a thumbnail and no way to act at all.
    func test_mediaWithNoRemoteAddressStillOffersATransfer() {
        var content = MessageContent(
            text: "",
            image: "/var/mobile/tmp/IMG_0042.jpg",
            shouldUploadDownload: false,
            shouldRetry: false
        )
        content.remoteUri = nil

        let message = MessageDataItem(
            codeMessage: "local-only-2",
            senderId: CurrentSessionInfo.shared.currentUid,
            typeMessage: .IMAGE,
            message: content,
            createdAt: Date()
        )

        XCTAssertNil(message.remoteMediaURLString)
        XCTAssertTrue(message.mediaNeedsTransfer)
    }

    /// `remoteUri` is the one field that only ever means the server's copy, so it
    /// is asked before anything else.
    func test_remoteUriWinsOverAStaleLocalImagePath() {
        var content = MessageContent(
            text: "",
            image: "/var/mobile/tmp/IMG_0042.jpg",
            shouldUploadDownload: false,
            shouldRetry: false
        )
        content.remoteUri = "https://cdn.example.com/real.jpg"

        let message = MessageDataItem(
            codeMessage: "mixed",
            senderId: CurrentSessionInfo.shared.currentUid,
            typeMessage: .IMAGE,
            message: content,
            createdAt: Date()
        )

        XCTAssertEqual(message.remoteMediaURLString, "https://cdn.example.com/real.jpg")
    }

    // MARK: - Batch scope

    /// A single control may only speak for a batch while every item is in the same
    /// state. It used to read `messages[0]` alone, so a batch whose first photo had
    /// gone and whose third had failed showed no control at all.
    /// A batch stops being one operation as soon as its items want to move in
    /// different directions — which is what a single control cannot express, and
    /// why the grid partitions before choosing one.
    ///
    /// Asserted on direction rather than on `mediaNeedsTransfer`: that reads the
    /// file system, and a test has no files on disk to read.
    func test_aDivergedBatchIsNotOneThing() {
        let batch = [
            sentImage(pending: false, failed: false, code: "a"),
            sentImage(pending: true, failed: true, code: "b")
        ]

        XCTAssertTrue(batch[0].mediaTransferIsDownload)
        XCTAssertFalse(batch[1].mediaTransferIsDownload)
    }

    func test_aFreshBatchIsOneThing() {
        let batch = [
            sentImage(pending: true, failed: false, code: "a"),
            sentImage(pending: true, failed: false, code: "b")
        ]

        XCTAssertTrue(batch.allSatisfy(\.mediaNeedsTransfer))
    }

}

private struct TransferPassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
