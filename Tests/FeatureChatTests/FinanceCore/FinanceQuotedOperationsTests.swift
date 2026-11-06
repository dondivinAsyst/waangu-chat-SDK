//
//  FinanceQuotedOperationsTests.swift
//  FeatureChatTests
//
//  Phase 5 — socle des opérations quotées (§5, « Pattern commun »).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceQuotedOperationsTests: XCTestCase {

    func test_routes_followTheContractPattern() {
        XCTAssertEqual(QuotedOperation.payBill.prepareRoute, "/financial/pay-bill/prepare")
        XCTAssertEqual(QuotedOperation.payBill.executeRoute, "/financial/pay-bill/execute")
        XCTAssertEqual(QuotedOperation.qr.executeRoute, "/financial/qr/execute")
        XCTAssertEqual(QuotedOperation.topUp.prepareRoute, "/financial/top-up/prepare")
        XCTAssertEqual(QuotedOperation.cashOut.executeRoute, "/financial/cash-out/execute")
        XCTAssertEqual(QuotedOperation.invoice.prepareRoute, "/financial/invoice/prepare")
    }

    /// `QuotedPrepareResponse` du contrat, plat : devis confirmable avec frais et total serveur.
    func test_quotedPrepareResponse_becomesAConfirmableQuote() async throws {
        let (services, server) = Self.make()
        let quote = try await services.quotedOperations
            .prepare(.payBill, body: ["billerId": "b_1"], idempotency: FinanceFixtures.idempotency(key: "bill-1")).get()

        XCTAssertEqual(quote.reference.id, "fco_bill")
        XCTAssertEqual(quote.amount, 15_000)
        XCTAssertEqual(quote.feeAmount, 100)
        XCTAssertEqual(quote.totalAmount, 15_100, "Le total est celui du serveur — jamais recalculé")
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/pay-bill/prepare" })
        XCTAssertEqual(call.headers["Idempotency-Key"], "bill-1")
    }

    /// Le devis d'une facture se confirme par le chemin de Send Money et part
    /// sur **son** execute, une seule fois, avec le `QuotedExecuteRequest` du contrat.
    func test_quotedOperation_executesOnItsOwnRoute_once() async throws {
        let (services, server) = Self.make()
        let quote = try await services.quotedOperations
            .prepare(.payBill, body: [:], idempotency: FinanceFixtures.idempotency()).get()

        let outcome = await FinanceSendMoneyTests.confirm(quote, services: services)

        guard case .executed = outcome else { return XCTFail("\(outcome)") }
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/send-money/execute") })
        let executes = calls.filter { $0.route == "POST /chat-core/financial/pay-bill/execute" }
        XCTAssertEqual(executes.count, 1)
        let body = executes[0].body
        for field in ["financialIntentRef", "conversationId", "confirmationId", "quoteId",
                      "objectVersion", "deviceId", "executionPermitId"] {
            XCTAssertNotNil(body[field], "QuotedExecuteRequest.\(field)")
        }
    }

    func test_quotedComplianceHold_isRefused() async {
        var routes = Self.routes()
        routes["POST /chat-core/financial/pay-bill/prepare"] = FinanceCoreJSON.wrap(
            #"{ "financialIntentRef": "fco_h", "status": "COMPLIANCE_HOLD", "processRequired": true }"#)
        let (services, _) = Self.make(routes)
        let result = await services.quotedOperations.prepare(.payBill, body: [:], idempotency: FinanceFixtures.idempotency())
        guard case .failure(.complianceBlocked) = result else { return XCTFail("\(result)") }
    }

    // MARK: - Fixtures

    static func make(_ routes: [String: String] = routes()) -> (FinanceCoreLiveServices, ScriptedChatCoreAPIClient) {
        let server = ScriptedChatCoreAPIClient(routes: routes)
        return (FinanceCoreLiveServices(apiClient: server, deviceID: { "dev_1" }), server)
    }

    static func routes() -> [String: String] {
        var routes = FinanceBootstrapTests.routes(resumeLocked: false)
        routes["POST /chat-core/financial/pay-bill/prepare"] = FinanceCoreJSON.wrap(#"""
        { "financialIntentRef": "fco_bill", "conversationId": "conv_1", "status": "READY_FOR_CONFIRMATION",
          "processRequired": false, "amountMinor": 15000, "currency": "BIF", "quoteId": "q_b1", "feeMinor": 100,
          "totalMinor": 15100, "fxRate": null, "quoteExpiresAt": "2099-09-09T12:02:00Z", "objectVersion": "v1-bb",
          "confirmation": { "confirmationId": "cfp_b1", "fingerprint": "fp", "expiresAt": "2099-09-09T12:02:00Z" },
          "merchantId": "m_1", "storeId": null, "terminalId": null, "executionPermitId": "perm_b1",
          "message": "Quote prêt — confirmation explicite requise.", "nextSafeActions": ["CONFIRM", "CANCEL"] }
        """#)
        routes["POST /chat-core/financial/pay-bill/execute"] = FinanceCoreJSON.wrap(
            #"{ "financialIntentRef": "fco_bill", "conversationId": "conv_1", "status": "SUBMITTED" }"#)
        routes["GET /chat-core/financial/objects/fco_bill"] = FinanceCoreJSON.wrap(
            FinanceObjectCardTests.cardJSON(status: "PROCESSING", tone: "PENDING", final: false)
                .replacingOccurrences(of: "fco_9c2e", with: "fco_bill"))
        return routes
    }
}
