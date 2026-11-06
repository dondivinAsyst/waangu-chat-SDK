import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatRoomE2EECoordinatorTests: XCTestCase {

    func test_decryptIncoming_returnsPlainTextUnchanged_whenNotEncrypted() async {
        let coordinator = ChatRoomE2EECoordinator(
            e2eeUseCases: StubE2EEUseCases(),
            pendingQueue: MockPendingE2EEQueue()
        )

        let message = MessageDataItem(
            codeMessage: "m1",
            senderId: "them",
            senderPhone: "111",
            senderName: "User",
            receiverId: "conv",
            groupId: "",
            typeMessage: .TEXT,
            message: MessageContent(text: "hello world"),
            status: .SENT,
            createdAt: Date()
        )

        let result = await coordinator.decryptIncoming(message, conversationId: "conv")
        XCTAssertEqual(result.message.text, "hello world")
    }

    func test_encryptOutgoingText_queuesWhenRecipientMissing() async {
        let queue = MockPendingE2EEQueue()
        let coordinator = ChatRoomE2EECoordinator(
            e2eeUseCases: StubE2EEUseCases(),
            pendingQueue: queue
        )

        let outcome = await coordinator.encryptOutgoingText(
            plaintext: "secret",
            codeMessage: "m2",
            conversationId: "conv",
            recipientId: ""
        )

        if case .queued = outcome {
            // expected
        } else {
            XCTFail("Expected queued outcome for missing recipient")
        }
        XCTAssertFalse(queue.hasItems(for: "conv"))
    }
}

// MARK: - Mock Classes

private class MockPendingE2EEQueue: PendingE2EEQueueProtocol {
    private var items: [String: [PendingE2EEQueueItem]] = [:]
    
    func enqueue(
        codeMessage: String,
        plaintext: String,
        conversationId: String,
        recipientUserId: String,
        messageType: String = "TEXT",
        groupId: String = ""
    ) throws {
        let item = PendingE2EEQueueItem(
            codeMessage: codeMessage,
            conversationId: conversationId,
            recipientUserId: recipientUserId,
            localEncryptedText: Data(plaintext.utf8),
            messageType: messageType,
            groupId: groupId,
            createdAt: Date()
        )
        items[conversationId, default: []].append(item)
    }
    
    func dequeueAll(for conversationId: String) -> [(plaintext: String, item: PendingE2EEQueueItem)] {
        let conversationItems = items[conversationId] ?? []
        items[conversationId] = []
        return conversationItems.map { (String(decoding: $0.localEncryptedText, as: UTF8.self), $0) }
    }
    
    func dequeueAll() -> [(plaintext: String, item: PendingE2EEQueueItem)] {
        let allItems = items.values.flatMap { $0 }
        items.removeAll()
        return allItems.map { (String(decoding: $0.localEncryptedText, as: UTF8.self), $0) }
    }
    
    func hasItems(for conversationId: String) -> Bool {
        return !(items[conversationId]?.isEmpty ?? true)
    }
    
    var isEmpty: Bool {
        return items.values.allSatisfy { $0.isEmpty }
    }
}

private struct StubE2EEUseCases: E2EEUseCasesProtocol {
    var encrypt: EncryptMessageUseCaseProtocol { StubEncrypt() }
    var decrypt: DecryptMessageUseCaseProtocol { StubDecrypt() }
    var hasSession: HasE2EESessionUseCaseProtocol { StubHasSession() }
    var generateKeyBundle: GenerateKeyBundleUseCaseProtocol { fatalError("not used") }
    var initiateSession: InitiateE2EESessionUseCaseProtocol { fatalError("not used") }
    var acceptSession: AcceptE2EESessionUseCaseProtocol { fatalError("not used") }
    var fetchKeyBundle: FetchKeyBundleUseCaseProtocol { fatalError("not used") }
    var uploadKeyBundle: UploadKeyBundleUseCaseProtocol { fatalError("not used") }
}

private struct StubEncrypt: EncryptMessageUseCaseProtocol {
    func execute(text: String, conversationId: String) async throws -> String { text }
}

private struct StubDecrypt: DecryptMessageUseCaseProtocol {
    func execute(encryptedText: String, conversationId: String) async throws -> String { encryptedText }
}

private struct StubHasSession: HasE2EESessionUseCaseProtocol {
    func execute(conversationId: String) async throws -> Bool { false }
}
