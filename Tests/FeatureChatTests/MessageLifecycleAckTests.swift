//
//  MessageLifecycleAckTests.swift
//  FeatureChatTests
//
//  Harness 360 — matrice miroir : édition, suppression, accusés de réception.
//  Chaque accusé serveur passe par `ChatSyncDelegate.processEvent`, contre la
//  vraie base SQLite, comme dans `SentReceiptOrderingTests`.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class MessageLifecycleAckTests: XCTestCase {

    private let me = "me"
    private let peer = "peer-1"
    private let serverTime = Date(timeIntervalSince1970: 1_791_000_000)

    // MARK: - Suppression

    func test_deleteAck_forEveryone_confirmsAndClearsSearchText() async throws {
        let (store, message) = try await seed(status: .pending, searchText: "bonjour", isDeleted: true, isDeletedForAll: true)

        let stored = try await receive("delete_ack", for: message, payload: ["forEveryone": true], in: store)

        XCTAssertTrue(stored.isDeleted)
        XCTAssertTrue(stored.isDeletedForAll)
        XCTAssertEqual(stored.deliveryStatus, .sent)
        XCTAssertNil(stored.searchText)
    }

    /// Le succès seul ne fait jamais d'une suppression « pour moi » une suppression pour tous.
    func test_deleteAck_withoutPayload_staysDeletedForMeOnly() async throws {
        let (store, message) = try await seed(status: .sent, searchText: "bonjour", isDeleted: true)

        let stored = try await receive("delete_ack", for: message, in: store)

        XCTAssertTrue(stored.isDeleted)
        XCTAssertFalse(stored.isDeletedForAll)
        XCTAssertNil(stored.searchText)
    }

    func test_deleteFailed_forEveryone_marksFailed() async throws {
        let (store, message) = try await seed(status: .pending, isDeleted: true, isDeletedForAll: true)

        let stored = try await receive("delete_failed", for: message, payload: ["forEveryone": true], in: store)

        XCTAssertEqual(stored.deliveryStatus, .failed)
    }

    // MARK: - Édition

    func test_modifyAck_withoutPayload_marksSent() async throws {
        let (store, message) = try await seed(status: .pending)

        let stored = try await receive("modify_ack", for: message, in: store)

        XCTAssertEqual(stored.deliveryStatus, .sent)
    }

    func test_modifyFailed_marksFailed() async throws {
        let (store, message) = try await seed(status: .pending)

        let stored = try await receive("modify_failed", for: message, in: store)

        XCTAssertEqual(stored.deliveryStatus, .failed)
    }

    // MARK: - Accusés de réception

    func test_deliveryReceipt_marksDelivered_andRecordsThePeer() async throws {
        let (store, message) = try await seed(status: .sent)

        let stored = try await receive("delivery_receipt", for: message, payload: deliveryPayload(message), in: store)

        XCTAssertEqual(stored.deliveryStatus, .delivered)
        let receipts = try await receipts(for: message, in: store)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.userId, peer)
        XCTAssertNotNil(receipts.first?.deliveredAt)
    }

    /// Un accusé livré deux fois est le même fait.
    func test_deliveryReceipt_twice_keepsOneReceipt() async throws {
        let (store, message) = try await seed(status: .sent)

        _ = try await receive("delivery_receipt", for: message, payload: deliveryPayload(message), in: store)
        _ = try await receive("delivery_receipt", for: message, payload: deliveryPayload(message), in: store)

        let receipts = try await receipts(for: message, in: store)
        XCTAssertEqual(receipts.count, 1)
    }

    /// Le statut n'est jamais rétrogradé par un accusé arrivé en retard.
    func test_lateDeliveryReceipt_afterRead_staysRead() async throws {
        let (store, message) = try await seed(status: .sent)

        _ = try await receive("read_receipt", for: message, in: store)
        let stored = try await receive("delivery_receipt", for: message, payload: deliveryPayload(message), in: store)

        XCTAssertEqual(stored.deliveryStatus, .read)
    }

    func test_deliveryReceipt_onDeletedMessage_isIgnored() async throws {
        let (store, message) = try await seed(status: .sent, isDeleted: true)

        let stored = try await receive("delivery_receipt", for: message, payload: deliveryPayload(message), in: store)

        XCTAssertEqual(stored.deliveryStatus, .sent)
        let receipts = try await receipts(for: message, in: store)
        XCTAssertTrue(receipts.isEmpty)
    }

    /// `read_ack` : la conversation est lue sur un autre appareil — les messages
    /// reçus passent à lu, les miens ne bougent pas.
    func test_readAck_clearsUnread_andMarksOnlyIncomingAsRead() async throws {
        let store = await Self.makeStore()
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct, unreadCount: 3)
        try await store.save(conversation)
        let incoming = MessageModel(conversationId: conversation.id, senderId: peer, senderName: "Peer",
                                    timestamp: serverTime, deliveryStatus: .delivered)
        let mine = MessageModel(conversationId: conversation.id, senderId: me, senderName: "Me",
                                timestamp: serverTime, deliveryStatus: .sent)
        try await store.save(incoming)
        try await store.save(mine)

        let event = ChatSyncEventDTO(type: "read_ack", referenceId: nil, conversationId: conversation.id,
                                     payload: nil, at: serverTime.timeIntervalSince1970)
        await makeDelegate().processEvent(event, database: store)

        let storedConversation = try await store.fetchOne(ConversationModel.self, id: conversation.id)
        XCTAssertEqual(storedConversation?.unreadCount, 0)
        let storedIncoming = try await store.fetchOne(MessageModel.self, id: incoming.id)
        XCTAssertEqual(storedIncoming?.deliveryStatus, .read)
        let storedMine = try await store.fetchOne(MessageModel.self, id: mine.id)
        XCTAssertEqual(storedMine?.deliveryStatus, .sent)
    }

    // MARK: - Outils

    private func seed(
        status: MessageDeliveryStatusModel,
        searchText: String? = nil,
        isDeleted: Bool = false,
        isDeletedForAll: Bool = false
    ) async throws -> (any DatabaseRepositoryProtocol, MessageModel) {
        let store = await Self.makeStore()
        // Un message n'existe qu'avec sa conversation (clé étrangère).
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let message = MessageModel(conversationId: conversation.id, senderId: me, senderName: "Me",
                                   searchText: searchText, timestamp: serverTime, deliveryStatus: status,
                                   isDeleted: isDeleted, isDeletedForAll: isDeletedForAll)
        try await store.save(message)
        return (store, message)
    }

    private func receive(
        _ type: String,
        for message: MessageModel,
        payload: [String: Any]? = nil,
        in store: any DatabaseRepositoryProtocol
    ) async throws -> MessageModel {
        let raw = try payload.map { AnyCodablePayload(rawData: try JSONSerialization.data(withJSONObject: $0)) }
        let event = ChatSyncEventDTO(type: type, referenceId: message.id, conversationId: message.conversationId,
                                     payload: raw, at: serverTime.timeIntervalSince1970)
        await makeDelegate().processEvent(event, database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: message.id)
        return try XCTUnwrap(stored)
    }

    private func deliveryPayload(_ message: MessageModel) -> [String: Any] {
        ["codeMessage": message.id, "conversationId": message.conversationId, "userId": peer,
         "deliveredAt": Int64(serverTime.timeIntervalSince1970 * 1_000)]
    }

    private func receipts(
        for message: MessageModel,
        in store: any DatabaseRepositoryProtocol
    ) async throws -> [ReadReceiptModel] {
        try await store.fetch(ReadReceiptModel.self,
                              query: QuerySpec(filter: FilterSpec("message_id == %@", .string(message.id))))
    }

    private func makeDelegate() -> ChatSyncDelegate {
        let me = self.me
        return ChatSyncDelegate(fieldCrypto: PassthroughFieldCrypto(), currentUserId: { me })
    }

    private static func makeStore() async -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
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
