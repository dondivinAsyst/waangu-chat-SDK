//
//  FinanceRequestResponseTests.swift
//  FeatureChatTests
//
//  Phase 4 — répondre à une demande : payer (un devis), refuser, relancer.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceRequestResponseTests: XCTestCase {

    private static let reference = FinanceFixtures.reference(type: .moneyRequest, id: "req_1", version: 0)

    static func answerRoutes() -> [String: String] { routes() }

    private static func routes() -> [String: String] {
        var routes = FinanceRequestMoneyTests.routes()
        routes["POST /chat-core/financial/request-money/pay"] =
            FinanceSendMoneyTests.prepareJSON(expiresAt: "2099-09-09T12:02:00Z")
        routes["POST /chat-core/financial/request-money/decline"] = FinanceCoreJSON.wrap("{}")
        return routes
    }

    /// « Ouvre un Send Money. Pas un débit magique. » — §4.
    func test_pay_returnsAQuoteToConfirm_andNeverExecutes() async throws {
        let (services, server) = FinanceRequestMoneyTests.make(Self.routes())

        let quote = try await services.moneyRequestResponder
            .pay(Self.reference, conversationID: "conv_1", amount: nil, currency: "BIF").get()

        XCTAssertEqual(quote.reference.id, "fco_9c2e", "Le devis est celui du prepare rendu par /pay")
        let calls = await server.calls
        let pay = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money/pay" })
        XCTAssertEqual(pay.body["requestRef"] as? String, "req_1")
        XCTAssertEqual(pay.body["conversationId"] as? String, "conv_1")
        XCTAssertNil(pay.body["amountMinor"], "Montant fixe : la part due est celle du serveur")
        // L'empreinte porte sur l'appareil : sans lui, l'execute était refusé
        // (« Confirmation fingerprint does not match context »).
        XCTAssertEqual(pay.body["deviceId"] as? String, "dev_1")
        XCTAssertEqual(pay.body["channel"] as? String, "MOBILE")
        XCTAssertNotNil(pay.headers["Idempotency-Key"])
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") }, "Aucun débit sans confirmation")
    }

    func test_decline_hitsItsRoute() async throws {
        let (services, server) = FinanceRequestMoneyTests.make(Self.routes())

        try await services.moneyRequestResponder.decline(Self.reference, conversationID: "conv_1").get()

        let calls = await server.calls
        let decline = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money/decline" })
        XCTAssertEqual(decline.body["requestRef"] as? String, "req_1")
    }

    // MARK: - Annuler (Phase 10)

    func test_cancel_hitsIntentCancel_withTheRequestRef() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/intent/cancel"] = FinanceCoreJSON.wrap("{}")
        let (services, server) = FinanceRequestMoneyTests.make(routes)

        let outcome = try await services.moneyRequestResponder.cancel(Self.reference, conversationID: "conv_1").get()

        XCTAssertEqual(outcome, .cancelled)
        let calls = await server.calls
        let cancel = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/intent/cancel" })
        XCTAssertEqual(cancel.body["financialIntentRef"] as? String, "req_1")
    }

    /// `CF_046` (202) : demandé, pas fait — jamais présenté comme une erreur.
    func test_cancel_CF046_isRequested_notAnError() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/intent/cancel"] = FinanceCoreJSON.error("CF_046")
        let (services, _) = FinanceRequestMoneyTests.make(routes)

        let outcome = try await services.moneyRequestResponder.cancel(Self.reference, conversationID: "conv_1").get()
        XCTAssertEqual(outcome, .requested)
    }

    // MARK: - Une seule lecture

    /// La carte et le magasin lisent la même demande : un seul GET.
    func test_cardAndStoreShareOneRead_andAnActionClearsIt() async throws {
        let (services, server) = FinanceRequestMoneyTests.make(Self.routes())
        let route = "GET /chat-core/financial/request-money/req_1"

        async let card = services.moneyRequestResponder.overlay(for: Self.reference)
        async let store = services.apiClient.refresh(Self.reference)
        _ = await card
        _ = try await store
        var reads = await server.calls.filter { $0.route == route }.count
        XCTAssertEqual(reads, 1)

        _ = await services.moneyRequestResponder.decline(Self.reference, conversationID: "conv_1")
        _ = await services.moneyRequestResponder.overlay(for: Self.reference)
        reads = await server.calls.filter { $0.route == route }.count
        XCTAssertEqual(reads, 2, "Après une action, la relecture part au serveur")
    }

    // MARK: - Ce que la demande dit à chacun

    private func request(_ json: String) throws -> RequestViewDTO {
        try JSONDecoder().decode(RequestViewDTO.self, from: Data(json.utf8))
    }

    private static let open = #"""
    { "requestRef": "req_1", "requesterUserId": "usr_me", "status": "OPEN", "amountMode": "FIXED",
      "currency": "BIF", "amountMinor": 3000,
      "parties": [ { "chatUserId": "usr_jean", "requestedMinor": 2000, "paidMinor": 500,
                     "remainingMinor": 1500, "currency": "BIF", "status": "PENDING" },
                   { "chatUserId": "usr_ana", "requestedMinor": 1000, "paidMinor": 1000,
                     "remainingMinor": 0, "currency": "BIF", "status": "PAID" } ],
      "nextSafeActions": ["pay", "DECLINE"] }
    """#

    /// Réponses telles que le serveur les rend (journal du 21/09) : le payeur
    /// reçoit `PAY_REQUEST` / `DECLINE_REQUEST`, le demandeur `REMIND`…
    private static let asPayer = #"""
    { "requestRef": "req_1", "requesterUserId": "100000000000000001", "status": "OPEN", "amountMode": "FIXED",
      "currency": "BIF", "amountMinor": 20000,
      "parties": [ { "chatUserId": "645a3503ddb88a00085da11b", "requestedMinor": 20000, "paidMinor": 0,
                     "remainingMinor": 20000, "currency": "BIF", "status": "PENDING" } ],
      "nextSafeActions": ["PAY_REQUEST", "DECLINE_REQUEST"] }
    """#
    private static let asRequester = #"""
    { "requestRef": "req_1", "requesterUserId": "645a3503ddb88a00085da11b", "status": "OPEN", "amountMode": "FIXED",
      "currency": "BIF", "amountMinor": 2000000,
      "parties": [ { "chatUserId": "100000000000000001", "requestedMinor": 2000000, "paidMinor": 0,
                     "remainingMinor": 2000000, "currency": "BIF", "status": "PENDING" } ],
      "nextSafeActions": ["WAIT", "REMIND", "ISSUE_PAYMENT_LINK", "CANCEL_INTENT"] }
    """#

    // MARK: - WAIT

    /// `WAIT` est un état, pas un geste : dit à côté des boutons proposés,
    /// jamais changé en bouton — la réponse réelle du serveur au demandeur.
    func test_wait_isShownAlongsideTheRequestersActions() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.asRequester), reference: Self.reference,
                                                        me: "645a3503ddb88a00085da11b")
        XCTAssertTrue(overlay.isWaiting)
        XCTAssertTrue(overlay.canRemind)
        XCTAssertTrue(overlay.canIssueLink)
        XCTAssertTrue(overlay.canCancel)
    }

    /// Sans `WAIT`, pas de ligne d'attente — c'est le serveur qui décide.
    func test_noWait_meansNoWaitingLine() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.asPayer), reference: Self.reference,
                                                        me: "645a3503ddb88a00085da11b")
        XCTAssertFalse(overlay.isWaiting)
    }

    /// Ma part déjà envoyée ou réglée : la ligne de part le dit, pas « en attente ».
    func test_wait_isHidden_onceMyShareIsSentOrPaid() {
        for status in ["PAYMENT_SUBMITTED", "PAID"] {
            let overlay = MoneyRequestOverlay(reference: Self.reference, status: .pending, isRequester: false,
                                              amountMode: .fixed, currency: "BIF", requestedTotal: 200,
                                              myRemaining: 0, nextSafeActions: ["WAIT"], pendingPartyUserIDs: [],
                                              myPartyStatus: status)
            XCTAssertFalse(overlay.isWaiting, status)
        }
    }

    func test_serverSpelling_payerGetsPayAndDecline() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.asPayer), reference: Self.reference,
                                                        me: "645a3503ddb88a00085da11b")
        XCTAssertTrue(overlay.canPay)
        XCTAssertTrue(overlay.canDecline)
        XCTAssertFalse(overlay.canRemind)
        XCTAssertEqual(overlay.myRemaining, 20000)
    }

    func test_serverSpelling_requesterGetsRemindAndCancel() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.asRequester), reference: Self.reference,
                                                        me: "645a3503ddb88a00085da11b")
        XCTAssertFalse(overlay.canPay)
        XCTAssertFalse(overlay.canDecline)
        XCTAssertTrue(overlay.canRemind)
        XCTAssertTrue(overlay.canCancel, "CANCEL_INTENT listé au demandeur")
    }

    /// Après le paiement, la demande reste `OPEN` mais ma part est envoyée :
    /// plus de « Payer » ni « Refuser », même si la liste traîne encore.
    func test_afterPaying_myShareIsSent_andButtonsDisappear() throws {
        let submitted = #"""
        { "requestRef": "req_1", "requesterUserId": "100000000000000001", "status": "OPEN", "amountMode": "FIXED",
          "currency": "BIF", "amountMinor": 500000,
          "parties": [ { "chatUserId": "645a3503ddb88a00085da11b", "requestedMinor": 500000, "paidMinor": 0,
                         "remainingMinor": 500000, "currency": "BIF", "status": "PAYMENT_SUBMITTED" } ],
          "nextSafeActions": ["PAY_REQUEST", "DECLINE_REQUEST"] }
        """#
        let overlay = LiveMoneyRequestResponder.overlay(try request(submitted), reference: Self.reference,
                                                        me: "645a3503ddb88a00085da11b")
        XCTAssertEqual(overlay.myShare, .paymentSent)
        XCTAssertFalse(overlay.canPay, "Jamais deux paiements pour une part")
        XCTAssertFalse(overlay.canDecline)
    }

    func test_paidAndDeclinedShares() {
        func share(_ status: String) -> MoneyRequestOverlay.MyShare? {
            MoneyRequestOverlay(reference: Self.reference, status: .pending, isRequester: false, amountMode: .fixed,
                                currency: "BIF", requestedTotal: nil, myRemaining: nil,
                                nextSafeActions: [], pendingPartyUserIDs: [], myPartyStatus: status).myShare
        }
        XCTAssertEqual(share("PAID"), .paid)
        XCTAssertEqual(share("declined"), .declined)
        XCTAssertNil(share("PENDING"))
    }

    func test_payerCannotCancelSomeoneElsesRequest() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.asPayer), reference: Self.reference,
                                                        me: "645a3503ddb88a00085da11b")
        XCTAssertFalse(overlay.canCancel)
    }

    /// Le payeur voit **sa** part restante, et les boutons que le serveur liste.
    func test_payerSeesTheirRemainingShare_andTheServersActions() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.open), reference: Self.reference, me: "usr_jean")
        XCTAssertFalse(overlay.isRequester)
        XCTAssertEqual(overlay.myRemaining, 1500)
        XCTAssertTrue(overlay.canPay)
        XCTAssertTrue(overlay.canDecline)
        XCTAssertFalse(overlay.canRemind)
    }

    /// Le demandeur ne paie ni ne refuse sa propre demande ; relancer suit le serveur.
    func test_requesterRemindsOnlyWhoStillOwes() throws {
        let overlay = LiveMoneyRequestResponder.overlay(try request(Self.open), reference: Self.reference, me: "usr_me")
        XCTAssertTrue(overlay.isRequester)
        XCTAssertFalse(overlay.canPay)
        XCTAssertFalse(overlay.canDecline)
        XCTAssertFalse(overlay.canRemind, "Sans REMIND du serveur, pas de relance")
        XCTAssertEqual(overlay.pendingPartyUserIDs, ["usr_jean"])
    }

    /// Plus de `PAY` dans la liste ⇒ plus de bouton — aucune règle locale.
    func test_noPayInNextSafeActions_meansNoPayButton() throws {
        let paid = #"""
        { "requestRef": "req_1", "requesterUserId": "usr_me", "status": "COMPLETED", "currency": "BIF",
          "amountMinor": 3000, "parties": [], "nextSafeActions": ["VIEW_RECEIPT"] }
        """#
        let overlay = LiveMoneyRequestResponder.overlay(try request(paid), reference: Self.reference, me: "usr_jean")
        XCTAssertFalse(overlay.canPay)
        XCTAssertFalse(overlay.canDecline)
    }
}
