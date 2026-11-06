import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

/// Bloc 1, lot 1.4 — la révision retenue par le store rejoint les messages.
///
/// Contre la vraie base SQLite du chat : ce qui est vérifié ici, c'est la
/// requête « messages par `paymentRef` » (un `json_extract` sur `json_payload`)
/// et la réécriture de la ligne que la conversation observe.
///
/// La base vit à un chemin fixe et survit au test : chaque test crée sa propre
/// conversation, et la supprime (les messages suivent, en cascade).
final class FinancialMessageProjectionTests: XCTestCase {

    private var store: (any DatabaseRepositoryProtocol)!
    private var conversationIDs: [String] = []
    private let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(
                engine: .sqlite,
                migrationSteps: ChatDatabaseRegistration.migrationSteps
            )
        )
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        self.store = store
    }

    override func tearDown() async throws {
        for id in conversationIDs {
            try? await store.delete(ConversationModel.self, id: id)
        }
        conversationIDs = []
        store = nil
    }

    // MARK: - Fixtures

    private func payload(
        id: String,
        version: Int,
        status: PaymentStatus = .processing,
        verification: FinancialCardVerification = .unverified
    ) -> FinancialCardPayload {
        FinancialCardPayload(
            reference: FinanceFixtures.reference(id: id, version: version),
            status: status,
            amount: 25_000,
            currency: "BIF",
            feeAmount: 375,
            counterpartyName: "Bénéficiaire",
            lastRefreshedAt: refreshedAt,
            verification: verification
        )
    }

    private func newConversation() async throws -> String {
        let id = "test-conv-\(UUID().lowercasedString)"
        conversationIDs.append(id)
        try await store.save(
            ConversationModel(id: id, serverId: nil, type: .direct,
                              lastMessageAt: refreshedAt, unreadCount: 0, createdAt: refreshedAt)
        )
        return id
    }

    /// Un message de paiement portant la carte `card`.
    private func seedMessage(
        showing card: FinancialCardPayload,
        in conversationID: String
    ) async throws -> String {
        var content = MessageContentModel.text("")
        content.applyFinancial(card)
        let id = "test-msg-\(UUID().lowercasedString)"
        try await store.save(
            MessageModel(id: id, conversationId: conversationID, senderId: "me",
                         senderName: "Moi", type: .payment, content: content,
                         timestamp: refreshedAt)
        )
        return id
    }

    private func card(ofMessage id: String) async throws -> FinancialCardPayload? {
        let model = try await store.fetchOne(MessageModel.self, id: id)
        return model.flatMap { MessageModelMapper.buildFinancial(from: $0.content) }
    }

    // MARK: - Projection

    /// Une lecture faite sous `PAYMENT` — le pointeur MQTT suppose ce type —
    /// ne fait jamais d'une demande d'argent un paiement reçu.
    func testReadUnderAnotherTypeNeverRetypesTheMessage() async throws {
        let conversation = try await newConversation()
        let objectID = "req-\(UUID().lowercasedString)"
        let request = FinancialCardPayload(
            reference: FinanceFixtures.reference(type: .moneyRequest, id: objectID, version: 1),
            status: .pending, amount: 10_000, currency: "BIF",
            lastRefreshedAt: refreshedAt, verification: .unverified)
        let message = try await seedMessage(showing: request, in: conversation)

        let rewritten = try await GRDBFinancialMessageProjection(store: store)
            .project(payload(id: objectID, version: 2, status: .completed, verification: .verified))

        XCTAssertEqual(rewritten, 0)
        let card = try await card(ofMessage: message)
        XCTAssertEqual(card?.reference.type, .moneyRequest)
        XCTAssertEqual(card?.status, .pending)
    }

    /// Toutes les occurrences d'une référence sont réécrites — et elles seules.
    func testNewRevisionReachesEveryMessageOfThatObject() async throws {
        let conversation = try await newConversation()
        let objectID = "obj-\(UUID().lowercasedString)"
        let otherID = "obj-\(UUID().lowercasedString)"
        let first = try await seedMessage(showing: payload(id: objectID, version: 1), in: conversation)
        let second = try await seedMessage(showing: payload(id: objectID, version: 1), in: conversation)
        let other = try await seedMessage(showing: payload(id: otherID, version: 1), in: conversation)

        let rewritten = try await GRDBFinancialMessageProjection(store: store)
            .project(payload(id: objectID, version: 2, status: .completed, verification: .verified))

        XCTAssertEqual(rewritten, 2)
        for id in [first, second] {
            let card = try await card(ofMessage: id)
            XCTAssertEqual(card?.reference.version, 2)
            XCTAssertEqual(card?.status, .completed)
            XCTAssertEqual(card?.verification, .verified)
        }
        let untouched = try await card(ofMessage: other)
        XCTAssertEqual(untouched?.reference.version, 1)
        XCTAssertEqual(untouched?.status, .processing)
    }

    func testOlderRevisionNeverOverwritesTheMessage() async throws {
        let conversation = try await newConversation()
        let objectID = "obj-\(UUID().lowercasedString)"
        let message = try await seedMessage(
            showing: payload(id: objectID, version: 5, status: .completed), in: conversation
        )

        let rewritten = try await GRDBFinancialMessageProjection(store: store)
            .project(payload(id: objectID, version: 3, status: .processing))

        XCTAssertEqual(rewritten, 0)
        let card = try await card(ofMessage: message)
        XCTAssertEqual(card?.reference.version, 5)
        XCTAssertEqual(card?.status, .completed)
    }

    /// À révision égale, seule la vérification bouge — et elle doit arriver.
    func testSameRevisionStillCarriesVerification() async throws {
        let conversation = try await newConversation()
        let objectID = "obj-\(UUID().lowercasedString)"
        let message = try await seedMessage(
            showing: payload(id: objectID, version: 4, verification: .unverified), in: conversation
        )

        try await GRDBFinancialMessageProjection(store: store)
            .project(payload(id: objectID, version: 4, verification: .verified))

        let card = try await card(ofMessage: message)
        XCTAssertEqual(card?.verification, .verified)
    }

    func testObjectWithoutMessageRewritesNothing() async throws {
        let rewritten = try await GRDBFinancialMessageProjection(store: store)
            .project(payload(id: "obj-\(UUID().lowercasedString)", version: 1))

        XCTAssertEqual(rewritten, 0)
    }

    // MARK: - Écriture / relecture

    /// `applyFinancial` et `buildFinancial` sont les deux moitiés d'un même
    /// format : ce qui est écrit doit se relire à l'identique.
    func testWrittenCardReadsBackUnchanged() {
        let written = payload(id: "obj-roundtrip", version: 7, status: .completed, verification: .verified)
        var content = MessageContentModel.text("")
        content.applyFinancial(written)

        let read = MessageModelMapper.buildFinancial(from: content)

        XCTAssertEqual(read?.reference.id, written.reference.id)
        XCTAssertEqual(read?.reference.type, written.reference.type)
        XCTAssertEqual(read?.reference.version, written.reference.version)
        XCTAssertEqual(read?.reference.correlationID, written.reference.correlationID)
        XCTAssertEqual(read?.status, written.status)
        XCTAssertEqual(read?.amount, written.amount)
        XCTAssertEqual(read?.currency, written.currency)
        XCTAssertEqual(read?.feeAmount, written.feeAmount)
        XCTAssertEqual(read?.counterpartyName, written.counterpartyName)
        XCTAssertEqual(read?.verification, written.verification)
        XCTAssertEqual(read?.lastRefreshedAt, written.lastRefreshedAt)
    }
}
