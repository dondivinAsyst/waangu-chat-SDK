//
//  FinanceBillPayTests.swift
//  FeatureChatTests
//
//  §5.1 — payer une facture : prepare (un devis), jamais un débit direct.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceBillPayTests: XCTestCase {

    /// `QuotedPrepareResponse` — exemple du contrat, dates dans le futur.
    private static let quotedPrepare = #"""
    {"financialIntentRef":"fco_bill_1","conversationId":null,"status":"READY_FOR_CONFIRMATION",
     "processRequired":false,"amountMinor":12500,"currency":"BIF","quoteId":"q_1","feeMinor":100,
     "totalMinor":12600,"fxRate":null,"quoteExpiresAt":"2099-09-09T12:02:00Z","objectVersion":"v1-x",
     "confirmation":{"confirmationId":"cfp_1","fingerprint":"f","expiresAt":"2099-09-09T12:02:00Z"},
     "executionPermitId":"perm_1","message":"Quote prêt","nextSafeActions":["CONFIRM","CANCEL"]}
    """#

    private static let bill = Bill(
        reference: FinanceFixtures.reference(type: .bill, id: "inq_stub_1", version: 0),
        billerID: "STUB_REGIE_EAU", customerLabel: "J*** D** · ****8990",
        amountDue: 12500, currency: "BIF", fetchedAt: Date(), allowsPartialPayment: false)

    func test_pay_returnsAQuote_fromPrepare_andNeverExecutes() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/pay-bill/prepare"] = FinanceCoreJSON.wrap(Self.quotedPrepare)
        let (services, server) = FinanceRequestMoneyTests.make(routes)

        let quote = try await services.bills.quote(
            Self.bill, amount: 12500, conversationID: "conv_1",
            idempotency: IdempotencyContext.new(deviceID: "dev_1")).get()

        XCTAssertEqual(quote.reference.id, "fco_bill_1")
        XCTAssertEqual(quote.reference.type, .bill)
        XCTAssertEqual(quote.feeAmount, 100)
        XCTAssertEqual(quote.totalAmount, 12600)

        let calls = await server.calls
        let prepare = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/pay-bill/prepare" })
        XCTAssertEqual(prepare.body["inquiryRef"] as? String, "inq_stub_1")
        XCTAssertEqual(prepare.body["billerId"] as? String, "STUB_REGIE_EAU")
        XCTAssertEqual((prepare.body["amountMinor"] as? NSNumber)?.int64Value, 12500)
        XCTAssertEqual(prepare.body["currency"] as? String, "BIF")
        // Chat Core refuse un prepare sans fil : « conversationId must not be blank ».
        XCTAssertEqual(prepare.body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(prepare.body["deviceId"] as? String, "dev_1")
        XCTAssertEqual(prepare.body["channel"] as? String, "MOBILE")
        XCTAssertNotNil(prepare.headers["Idempotency-Key"])
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") }, "Aucun débit sans confirmation")
    }

    /// Le paiement direct est fermé : il n'existe que devis → confirmation.
    func test_directPay_isClosed() async {
        let (services, server) = FinanceRequestMoneyTests.make(FinanceSendMoneyTests.routes())
        let result = await services.bills.pay(Self.bill, amount: 12500,
                                              idempotency: IdempotencyContext.new(deviceID: "dev_1"))
        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.contains("pay-bill") })
    }

    // MARK: - §5.1.0 Requery — paiement et prise en compte, distincts

    private static func requeried(_ overlay: String) async throws -> (PaymentStatus, [ScriptedChatCoreAPIClient.Call]) {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/pay-bill/requery"] = FinanceCoreJSON.wrap(overlay)
        let (services, server) = FinanceRequestMoneyTests.make(routes)
        let reference = FinanceFixtures.reference(type: .bill, id: "fco_bill_1", version: 1)
        let status = try await services.bills.requery(reference).get()
        return (status, await server.calls)
    }

    func test_requeryRoute_followsTheContract() {
        let endpoint = ChatFinanceEndpoints.billRequery(.init(financialIntentRef: "fco_1", conversationId: nil))
        XCTAssertEqual(endpoint.path, "/chat-core/financial/pay-bill/requery")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters?["financialIntentRef"] as? String, "fco_1")
    }

    /// **Le cas qui compte.** Débit réglé, facturier pas encore à jour : c'est le
    /// `BILLER_NOT_UPDATED` des litiges, pas un succès — et aucun execute ne part.
    func test_requery_paidButNotFulfilled_isNotASuccess() async throws {
        let (status, calls) = try await Self.requeried(
            #"{"financialIntentRef":"fco_bill_1","paymentStatus":"SUBMITTED","settlementStatus":"PENDING","fulfillmentStatus":"PENDING"}"#)
        XCTAssertNotEqual(status, .completed)

        let (settled, _) = try await Self.requeried(
            #"{"financialIntentRef":"fco_bill_1","paymentStatus":"SETTLED","fulfillmentStatus":"PENDING"}"#)
        XCTAssertEqual(settled, .pendingReconciliation)
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") }, "Relire, jamais rejouer")
    }

    func test_requery_fulfilled_isASuccess() async throws {
        let (status, _) = try await Self.requeried(
            #"{"financialIntentRef":"fco_bill_1","paymentStatus":"COMPLETED","fulfillmentStatus":"FULFILLED"}"#)
        XCTAssertEqual(status, .completed)
    }
}
