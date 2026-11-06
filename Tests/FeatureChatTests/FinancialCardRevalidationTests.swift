import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Bloc 1 §8 et §11.2 — quelles cartes sont relues, et avec quelle référence.
final class FinancialCardRevalidationTests: XCTestCase {

    private func message(_ reference: FinancialReference, status: PaymentStatus?,
                         verification: FinancialCardVerification = .verified) -> MessageDataItem {
        let payload = status.map {
            FinancialCardPayload(reference: reference, status: $0, amount: 1_000, currency: "BIF",
                                 verification: verification)
        }
        return FinanceConversationMessage.make(reference: reference, payload: payload,
                                               groupID: nil, receiverID: "peer")
    }

    func testVerifiedFinalCardIsNotReread() {
        let done = message(FinanceFixtures.reference(id: "done"), status: .completed)
        XCTAssertTrue(FinancialCardRevalidation.references(in: [done]).isEmpty)
    }

    func testMovingUnprovenAndPendingCardsAreReread() {
        let moving = message(FinanceFixtures.reference(id: "moving"), status: .processing)
        let unproven = message(FinanceFixtures.reference(id: "unproven"), status: .completed,
                               verification: .unverified)
        let pending = message(FinanceFixtures.reference(id: "pending"), status: nil)

        let ids = FinancialCardRevalidation.references(in: [moving, unproven, pending]).map(\.id)
        XCTAssertEqual(Set(ids), ["moving", "unproven", "pending"])
    }

    /// Une carte d'attente est relue sous **sa** nature — une demande reste
    /// une demande. Sans nature connue, elle n'est pas relue.
    func testPendingCardIsReadUnderItsOwnType_neverAGuess() {
        let request = message(FinanceFixtures.reference(type: .moneyRequest, id: "req-1"), status: nil)
        XCTAssertEqual(FinancialCardRevalidation.reference(for: request)?.type, .moneyRequest)

        var untyped = request
        untyped.message.financialObjectType = nil
        XCTAssertNil(FinancialCardRevalidation.reference(for: untyped))
    }

    func testMostRecentFirst_capped_andDeduplicated() {
        let messages = (0..<30).map {
            message(FinanceFixtures.reference(id: "obj-\($0)"), status: .processing)
        } + [message(FinanceFixtures.reference(id: "obj-29"), status: .processing)]

        let ids = FinancialCardRevalidation.references(in: messages).map(\.id)
        XCTAssertEqual(ids.count, FinancialCardRevalidation.limit)
        XCTAssertEqual(ids.first, "obj-29")
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Référence d'un message arrivé

    func testArrivedMessageCarriesItsTypeButNeverItsRevision() {
        var content = MessageContentModel.text("")
        content.paymentRef = "req-1"
        content.financialObjectType = FinancialObjectType.moneyRequest.rawValue
        content.financialObjectVersion = 7
        let model = MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                                 type: .payment, content: content)

        let reference = ChatSyncDelegate.financialReference(of: model)
        XCTAssertEqual(reference?.id, "req-1")
        XCTAssertEqual(reference?.type, .moneyRequest)
        XCTAssertEqual(reference?.version, 0, "La révision vient du serveur, pas du message")
    }

    /// Sans nature sur le fil, aucune lecture : la deviner (`PAYMENT`)
    /// affichait une demande d'argent comme « Argent reçu ».
    func testArrivedMessageWithoutTypeIsNotRead_andTextIsIgnored() {
        var content = MessageContentModel.text("")
        content.paymentRef = "req-1"
        let untyped = MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                                   type: .payment, content: content)
        XCTAssertNil(ChatSyncDelegate.financialReference(of: untyped))

        let text = MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                                type: .text, content: content)
        XCTAssertNil(ChatSyncDelegate.financialReference(of: text))
    }
}
