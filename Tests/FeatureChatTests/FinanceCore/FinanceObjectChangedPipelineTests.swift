//
//  FinanceObjectChangedPipelineTests.swift
//  FeatureChatTests
//
//  Du pointeur MQTT réel (tel que le backend l'envoie) jusqu'au handler qui
//  relit la carte — INTEGRATION_CHAT_FINANCE.md §7 : après `OBJECT_CHANGED`,
//  refetch la carte.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class FinanceObjectChangedPipelineTests: XCTestCase {

    /// Copie exacte d'un pointeur reçu en production (22/09, 13:54:24).
    private static let versionedPointer = #"""
    {"eventType":"conversation.financial.object_changed","payload":{"action":"OBJECT_CHANGED","eventType":"conversation.financial.object_changed","originalEventType":"conversation.financial_status.projected","eventId":"3d3f95a4-4f57-4116-8731-95283f80418d","schemaVersion":"1.0.0","tenantId":null,"subject":{"conversationId":"195cc972-827a-3b33-8b11-688afc8dfc84","financialIntentRef":"cb84892d-ef62-4b2e-860b-7d0988d68e31"},"objectVersion":"v326-279e17b7-d255-42f3-9ed8-447ba8fd8341","correlationId":"3d3f95a4-4f57-4116-8731-95283f80418d","occurredAt":"2026-09-22T13:54:23.392335700Z","serverTime":"2026-09-22T13:54:24.516Z","refetchPath":"/v1/chat/financial/objects/cb84892d-ef62-4b2e-860b-7d0988d68e31","conversationId":"195cc972-827a-3b33-8b11-688afc8dfc84"},"conversationId":"195cc972-827a-3b33-8b11-688afc8dfc84","oldConversationId":null,"conversationType":null,"kind":null,"communityId":null,"channelId":null,"teamId":null,"senderName":null,"internalSenderName":null,"muted":false,"suppressNotification":false,"timestamp":"2026-09-22T13:54:24.519Z","processingTimeMs":3,"version":1}
    """#

    /// Son jumeau sans révision, reçu juste avant.
    private static let unversionedPointer = #"""
    {"eventType":"conversation.financial.object_changed","payload":{"action":"OBJECT_CHANGED","eventType":"conversation.financial.object_changed","originalEventType":"conversation.financial_status.projected","eventId":"77be1a6c-636f-4033-a383-cec209db3f0b","schemaVersion":"1.0.0","tenantId":null,"subject":{"conversationId":"195cc972-827a-3b33-8b11-688afc8dfc84","financialIntentRef":"cb84892d-ef62-4b2e-860b-7d0988d68e31"},"objectVersion":null,"correlationId":"77be1a6c-636f-4033-a383-cec209db3f0b","occurredAt":"2026-09-22T13:54:23.390732800Z","serverTime":"2026-09-22T13:54:24.500Z","refetchPath":"/v1/chat/financial/objects/cb84892d-ef62-4b2e-860b-7d0988d68e31","conversationId":"195cc972-827a-3b33-8b11-688afc8dfc84"},"conversationId":"195cc972-827a-3b33-8b11-688afc8dfc84","oldConversationId":null,"conversationType":null,"kind":null,"communityId":null,"channelId":null,"teamId":null,"senderName":null,"internalSenderName":null,"muted":false,"suppressNotification":false,"timestamp":"2026-09-22T13:54:24.507Z","processingTimeMs":7,"version":1}
    """#

    private actor Received {
        var references: [FinancialReference] = []
        func add(_ reference: FinancialReference) { references.append(reference) }
    }

    private func deliver(_ json: String) async throws -> [FinancialReference] {
        let received = Received()
        let delegate = ChatSyncDelegate(
            fieldCrypto: PassthroughCrypto(),
            onFinancialObjectChanged: { await received.add($0) }
        )
        let event = try XCTUnwrap(ChatMqttEventParser.parse(data: Data(json.utf8)))
        await delegate.processEvent(event, database: await Self.makeStore())
        return await received.references
    }

    func test_realPointer_reachesTheHandler_withIdAndRevision() async throws {
        let references = try await deliver(Self.versionedPointer)

        let reference = try XCTUnwrap(references.first, "Le pointeur doit déclencher une relecture")
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(reference.id, "cb84892d-ef62-4b2e-860b-7d0988d68e31")
        XCTAssertEqual(reference.version, 326)
    }

    func test_unversionedPointer_stillReachesTheHandler() async throws {
        let references = try await deliver(Self.unversionedPointer)
        XCTAssertEqual(references.first?.id, "cb84892d-ef62-4b2e-860b-7d0988d68e31")
    }

    // MARK: - Pointeurs en double

    private func stored(version: Int) -> FinancialCardPayload {
        FinancialCardPayload(reference: FinanceFixtures.reference(version: version),
                             status: .processing, amount: 1000, currency: "BIF")
    }

    /// Le jumeau versionné arrive après la relecture du premier : rien à relire.
    func test_versionedTwin_isSkipped_onceTheStoreHoldsThatRevision() {
        let pointer = FinanceFixtures.reference(version: 326)
        XCTAssertTrue(ChatFeature.pointerIsAlreadyKnown(pointer, current: stored(version: 326)))
        XCTAssertTrue(ChatFeature.pointerIsAlreadyKnown(pointer, current: stored(version: 400)))
    }

    /// Une révision plus récente que le magasin se relit.
    func test_newerRevision_isRead() {
        let pointer = FinanceFixtures.reference(version: 327)
        XCTAssertFalse(ChatFeature.pointerIsAlreadyKnown(pointer, current: stored(version: 326)))
    }

    /// Sans révision, ou objet inconnu : toujours relire.
    func test_unversionedOrUnknown_isAlwaysRead() {
        XCTAssertFalse(ChatFeature.pointerIsAlreadyKnown(FinanceFixtures.reference(version: 0),
                                                         current: stored(version: 326)))
        XCTAssertFalse(ChatFeature.pointerIsAlreadyKnown(FinanceFixtures.reference(version: 5), current: nil))
    }

    private static func makeStore() async -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }
}

private struct PassthroughCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
