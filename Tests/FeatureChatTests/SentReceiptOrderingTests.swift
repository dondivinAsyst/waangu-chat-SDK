//
//  SentReceiptOrderingTests.swift
//  FeatureChatTests
//
//  B28, Harness §37 — l'ordre serveur fait foi, pas l'horloge du téléphone.
//  L'accusé d'envoi remplace l'heure locale du message par celle du serveur.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class SentReceiptOrderingTests: XCTestCase {

    /// Téléphone en avance d'une heure : l'heure posée à l'envoi est fausse.
    private let deviceClock = Date().addingTimeInterval(3_600)
    private let serverTime = Date(timeIntervalSince1970: 1_791_000_000)

    private func sendAndReceive(_ type: String) async throws -> MessageModel {
        let store = await Self.makeStore()
        // Un message n'existe qu'avec sa conversation (clé étrangère).
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let message = MessageModel(conversationId: conversation.id, senderId: "me", senderName: "Me",
                                   timestamp: deviceClock, deliveryStatus: .pending)
        try await store.save(message)

        let delegate = ChatSyncDelegate(fieldCrypto: PassthroughFieldCrypto())
        let receipt = ChatSyncEventDTO(type: type, referenceId: message.id, conversationId: message.conversationId,
                                       payload: nil, at: serverTime.timeIntervalSince1970)
        await delegate.processEvent(receipt, database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: message.id)
        return try XCTUnwrap(stored)
    }

    func test_sentReceipt_replacesTheDeviceClock_withTheServerTime() async throws {
        let stored = try await sendAndReceive("sent_receipt")
        XCTAssertEqual(stored.deliveryStatus, .sent)
        XCTAssertEqual(stored.timestamp.timeIntervalSince1970, serverTime.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Un échec d'envoi n'a pas d'heure serveur à faire valoir : l'heure ne bouge pas.
    func test_sendFailure_keepsTheOriginalTime() async throws {
        let stored = try await sendAndReceive("send_failed")
        XCTAssertEqual(stored.deliveryStatus, .failed)
        XCTAssertEqual(stored.timestamp.timeIntervalSince1970, deviceClock.timeIntervalSince1970, accuracy: 0.001)
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
