//
//  FinancialObjectSourceTests.swift
//  FeatureChatTests
//
//  Bloc 5 §6, §11 — d'où un objet financier peut venir, et ce qu'un état
//  technique devient sur le client.
//
//  Un objet financier ne naît que d'un message typé paiement portant une
//  référence et un type connus — jamais du texte libre. Un état technique de
//  l'EIG qui atteindrait le client n'est jamais un état métier : il devient
//  `unknown`, se relit, et ne s'affiche jamais comme réglé.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinancialObjectSourceTests: XCTestCase {

    private let crypto = PassthroughFieldCrypto()

    // MARK: - Texte libre

    /// Le texte décrit un paiement réglé, avec montant, référence et type :
    /// c'est du texte, pas un objet financier.
    func test_freeTextDescribingAPayment_producesNoFinancialObject() throws {
        let model = try inbound(type: "TEXT", content: [
            "text": "Paiement confirmé : 500 BIF, réf pay-123, type PAYMENT, statut COMPLETED"
        ])

        XCTAssertEqual(model.type, .text)
        XCTAssertNil(ChatSyncDelegate.financialReference(of: model))
    }

    /// Un message texte qui glisse les champs financiers dans son contenu
    /// reste un message texte : le type déclaré décide, pas le contenu.
    func test_textMessageSmugglingFinancialFields_producesNoFinancialObject() throws {
        let model = try inbound(type: "TEXT", content: [
            "text": "regarde", "paymentRef": "pay-123", "financialObjectType": "PAYMENT"
        ])

        XCTAssertNil(ChatSyncDelegate.financialReference(of: model))
    }

    func test_paymentMessageWithoutReference_producesNoFinancialObject() throws {
        let model = try inbound(type: "PAYMENT", content: ["financialObjectType": "PAYMENT"])

        XCTAssertNil(ChatSyncDelegate.financialReference(of: model))
    }

    /// Un type que cette version ne connaît pas n'est pas deviné.
    func test_paymentMessageWithUnknownType_producesNoFinancialObject() throws {
        let model = try inbound(type: "PAYMENT", content: [
            "paymentRef": "pay-123", "financialObjectType": "SOMETHING_NEW"
        ])

        XCTAssertNil(ChatSyncDelegate.financialReference(of: model))
    }

    /// Bloc 10 — les types du manifeste Waangu School, inconnus de cette version :
    /// carte générique, aucune référence financière, donc aucune action possible.
    /// Un serveur qui les enverrait avant que le client les connaisse ne
    /// déclenche ni lecture financière ni paiement.
    func test_schoolManifestTypes_areUnknown_andNeverExecutable() throws {
        for raw in ["SCHOOL_FEE", "INVOICE_REFERENCE"] {
            let decoded = try JSONDecoder().decode(FinancialObjectType.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decoded, .unknown, raw)
            XCTAssertFalse(decoded.isKnown, raw)

            let model = try inbound(type: "PAYMENT", content: [
                "paymentRef": "school-123", "financialObjectType": raw
            ])
            XCTAssertNil(ChatSyncDelegate.financialReference(of: model), raw)
        }
    }

    /// Témoin : un vrai message de paiement typé donne bien sa référence.
    func test_typedPaymentMessage_producesItsReference() throws {
        let model = try inbound(type: "PAYMENT", content: [
            "paymentRef": "pay-123", "financialObjectType": "MONEY_REQUEST", "financialCorrelationId": "corr-9"
        ])

        let reference = try XCTUnwrap(ChatSyncDelegate.financialReference(of: model))
        XCTAssertEqual(reference.id, "pay-123")
        XCTAssertEqual(reference.type, .moneyRequest)
    }

    // MARK: - États techniques de l'EIG

    private let eigStates = [
        "EIG_REQUESTED", "EIG_DISPATCHED", "EIG_ACKNOWLEDGED", "EIG_PENDING",
        "EIG_TIMEOUT", "EIG_TECHNICAL_FAILED", "EIG_CALLBACK_RECEIVED"
    ]

    /// EIG_ACKNOWLEDGED ≠ PAYMENT_COMPLETED ; EIG_TIMEOUT ≠ FAILED.
    func test_eigTechnicalStates_decodeAsUnknown_neverAsABusinessState() throws {
        for raw in eigStates {
            let status = try JSONDecoder().decode(PaymentStatus.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(status, .unknown, raw)
        }
    }

    func test_eigTechnicalStates_areReread_andNeverShownAsSettled() throws {
        for raw in eigStates {
            let status = try JSONDecoder().decode(PaymentStatus.self, from: Data("\"\(raw)\"".utf8))
            let card = FinancialCardPayload(reference: FinanceFixtures.reference(version: 1), status: status,
                                            amount: 1000, currency: "BIF", verification: .verified)

            XCTAssertTrue(card.needsReconciliation, raw)
            XCTAssertFalse(card.canPresentAsSettled, raw)
        }
    }

    // MARK: - Outils

    private func inbound(type: String, content: [String: Any]) throws -> MessageModel {
        let contentJSON = String(data: try JSONSerialization.data(withJSONObject: content), encoding: .utf8)!
        let payload: [String: Any] = ["codeMessage": "m-\(UUID().uuidString)", "senderId": "peer", "senderName": "Peer",
                                      "conversationId": "c", "content": contentJSON, "typeMessage": type,
                                      "timestamp": 1_791_000_000]
        let dto = try JSONDecoder().decode(InboundMessageDTO.self, from: JSONSerialization.data(withJSONObject: payload))
        return try XCTUnwrap(MessageModelMapper.toModel(from: dto, fieldCrypto: crypto))
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
