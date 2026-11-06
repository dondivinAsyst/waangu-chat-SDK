import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// La taxonomie partagée par iOS, Android et Web — et le type que chaque
/// opération publie.
final class FinancialObjectTypeTests: XCTestCase {

    func testWireValuesMatchTheSharedTaxonomy() {
        let expected: [FinancialObjectType: String] = [
            .moneyRequest: "MONEY_REQUEST", .payment: "PAYMENT", .bill: "BILL",
            .airtime: "AIRTIME", .dataBundle: "DATA_BUNDLE", .remittance: "REMITTANCE",
            .fxQuote: "FX_QUOTE", .merchantPayment: "MERCHANT_PAYMENT",
            .cashIn: "CASH_IN", .cashOut: "CASH_OUT", .refund: "REFUND", .dispute: "DISPUTE",
            .credit: "CREDIT", .investment: "INVESTMENT", .savings: "SAVINGS", .card: "CARD",
            .settlement: "SETTLEMENT", .payout: "PAYOUT", .splitBill: "SPLIT_BILL",
        ]
        for (type, raw) in expected { XCTAssertEqual(type.rawValue, raw) }
    }

    /// Une valeur d'un client plus récent ne casse pas le décodage.
    func testUnrecognisedValueDecodesAsUnknown_andIsNeverRead() throws {
        let decoded = try JSONDecoder().decode([FinancialObjectType].self,
                                               from: Data(#"["PAYMENT","LOAN"]"#.utf8))
        XCTAssertEqual(decoded, [.payment, .unknown])
        XCTAssertFalse(FinancialObjectType.unknown.isKnown)
    }

    /// Chaque prepare publie sa propre nature — plus jamais `PAYMENT` pour tous.
    func testEachQuotedOperationPublishesItsOwnType() {
        XCTAssertEqual(QuotedOperation.sendMoney.objectType, .payment)
        XCTAssertEqual(QuotedOperation.payBill.objectType, .bill)
        XCTAssertEqual(QuotedOperation.topUp.objectType, .airtime)
        XCTAssertEqual(QuotedOperation.invoice.objectType, .merchantPayment)
        XCTAssertEqual(QuotedOperation.cashIn.objectType, .cashIn)
        XCTAssertEqual(QuotedOperation.cashOut.objectType, .cashOut)
        XCTAssertEqual(QuotedOperation.qr.objectType, .payment)
    }

    /// Un message au type inconnu garde la carte générique et n'est jamais lu.
    func testUnknownTypeIsNotReadOnArrival() {
        var content = MessageContentModel.text("")
        content.paymentRef = "obj-1"
        content.financialObjectType = "unknown"
        let model = MessageModel(conversationId: "c", senderId: "peer", senderName: "Peer",
                                 type: .payment, content: content)
        XCTAssertNil(ChatSyncDelegate.financialReference(of: model))
    }
}
