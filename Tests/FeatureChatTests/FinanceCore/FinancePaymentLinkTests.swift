//
//  FinancePaymentLinkTests.swift
//  FeatureChatTests
//
//  Phase 4 — lien de paiement : émis pour une demande, jamais exécutable ;
//  inspecté pour le contexte seulement, puis payé par `/request-money/pay`.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinancePaymentLinkTests: XCTestCase {

    private static let reference = FinanceFixtures.reference(type: .moneyRequest, id: "req_1", version: 0)

    private static let linkJSON = #"""
    {"token":"lnk_1","nonce":"n_1","requestRef":"req_1","conversationId":"conv_1",
     "expiresAt":"2099-09-09T18:00:00Z","executable":false,"consumedAt":null}
    """#

    private static func routes() -> [String: String] {
        var routes = FinanceRequestMoneyTests.routes()
        routes["POST /chat-core/financial/request-money/payment-link"] = FinanceCoreJSON.wrap(linkJSON)
        routes["POST /chat-core/financial/request-money/payment-link/inspect"] = FinanceCoreJSON.wrap(linkJSON)
        return routes
    }

    func test_issue_namesTheRequest_underAnIdempotencyKey() async throws {
        let (services, server) = FinanceRequestMoneyTests.make(Self.routes())

        let link = try await services.moneyRequestResponder
            .issueLink(for: Self.reference, conversationID: "conv_1").get()

        XCTAssertEqual(link.token, "lnk_1")
        XCTAssertEqual(link.nonce, "n_1")
        XCTAssertEqual(link.requestRef, "req_1")
        XCTAssertFalse(link.executable, "Un lien ne paie jamais")
        XCTAssertTrue(link.isUsable(at: Date()))

        let calls = await server.calls
        let issue = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money/payment-link" })
        XCTAssertEqual(issue.body["requestRef"] as? String, "req_1")
        XCTAssertEqual(issue.body["conversationId"] as? String, "conv_1")
        let key = try XCTUnwrap(issue.headers["Idempotency-Key"])
        XCTAssertEqual(issue.body["idempotencyKey"] as? String, key, "Même clé en-tête et corps — sinon CF_071")
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") || $0.route.hasSuffix("/pay") })
    }

    /// Inspecter rend le contexte seulement : la demande désignée, relue par
    /// `GET /request-money/{ref}`. Rien n'est payé.
    func test_inspect_returnsTheRequest_andPaysNothing() async throws {
        let (services, server) = FinanceRequestMoneyTests.make(Self.routes())

        let overlay = try await services.moneyRequestResponder.inspectLink(token: "lnk_1", nonce: "n_1").get()

        XCTAssertEqual(overlay.reference.id, "req_1")
        let calls = await server.calls
        let inspect = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money/payment-link/inspect" })
        XCTAssertEqual(inspect.body["token"] as? String, "lnk_1")
        XCTAssertEqual(inspect.body["nonce"] as? String, "n_1")
        XCTAssertTrue(calls.contains { $0.route == "GET /chat-core/financial/request-money/req_1" })
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/pay") || $0.route.hasSuffix("/execute") })
    }

    /// Le contexte n'est pas publié : la demande peut y être imbriquée.
    func test_inspect_findsANestedRequestRef() {
        let nested: JSONValue = .dictionary(["link": .dictionary(["requestRef": .string("req_9")])])
        XCTAssertEqual(LiveMoneyRequestResponder.requestRef(in: nested), "req_9")
        XCTAssertNil(LiveMoneyRequestResponder.requestRef(in: .dictionary(["token": .string("x")])))
    }

    func test_inspect_invalidLink_CF036_isARefusal() async {
        var routes = Self.routes()
        routes["POST /chat-core/financial/request-money/payment-link/inspect"] = FinanceCoreJSON.error("CF_036")
        let (services, _) = FinanceRequestMoneyTests.make(routes)

        let result = await services.moneyRequestResponder.inspectLink(token: "bad", nonce: "n")

        guard case .failure = result else { return XCTFail("CF_036 doit être un refus") }
    }

    func test_consumedOrExpiredLink_isNotShareable() {
        let consumed = MoneyRequestLink(token: "t", nonce: "n", requestRef: "r", conversationID: nil,
                                        expiresAt: nil, executable: false, consumedAt: Date())
        let expired = MoneyRequestLink(token: "t", nonce: "n", requestRef: "r", conversationID: nil,
                                       expiresAt: Date(timeIntervalSinceNow: -60), executable: false, consumedAt: nil)
        XCTAssertFalse(consumed.isUsable())
        XCTAssertFalse(expired.isUsable())
    }

    /// L'adresse partagée : le schéma de l'app, jeton et nonce seulement.
    func test_sharedURL_carriesOnlyTokenAndNonce() throws {
        let url = try XCTUnwrap(PaymentLinkURL.make(token: "lnk_1", nonce: "n/1+2"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "waangu")
        XCTAssertEqual(parts.host, "chat")
        XCTAssertEqual(parts.path, "/pay-link")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "token" }?.value, "lnk_1")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "nonce" }?.value, "n/1+2", "Encodé puis relu à l'identique")
        XCTAssertEqual(parts.queryItems?.count, 2, "Ni montant ni bénéficiaire dans l'URL")
    }

    /// Le scanner reconnaît un QR de lien : il n'a rien à demander à
    /// `/qr/parse`, qui ne connaît que les points d'acceptation marchands.
    func test_scannedLinkURL_isReadBackAsTokenAndNonce() throws {
        let url = try XCTUnwrap(PaymentLinkURL.make(token: "lnk_1", nonce: "n/1+2"))
        let read = try XCTUnwrap(PaymentLinkURL.read(url.absoluteString))
        XCTAssertEqual(read.token, "lnk_1")
        XCTAssertEqual(read.nonce, "n/1+2")
    }

    func test_otherPayloads_areNotTakenForLinks() {
        // QR marchand EMV, lien d'une autre app, route Waangu voisine.
        for payload in ["00020101021226…", "https://example.com/pay?token=a&nonce=b",
                        "waangu://chat/conversation/123",
                        "waangu://chat/pay-link?token=lnk_1"] {
            XCTAssertNil(PaymentLinkURL.read(payload), payload)
        }
    }

    /// La demande lue porte sa conversation : c'est là qu'on la paie.
    func test_inspectedRequest_carriesItsConversation() async throws {
        let (services, _) = FinanceRequestMoneyTests.make(Self.routes())
        let overlay = try await services.moneyRequestResponder.inspectLink(token: "lnk_1", nonce: "n_1").get()
        XCTAssertNotNil(overlay.conversationID)
    }

    /// Le bouton n'apparaît que si le serveur propose `ISSUE_PAYMENT_LINK` au demandeur.
    func test_linkButton_followsTheServer() {
        func overlay(requester: Bool, actions: Set<String>) -> MoneyRequestOverlay {
            MoneyRequestOverlay(reference: Self.reference, status: .pending, isRequester: requester,
                                amountMode: .fixed, currency: "BIF", requestedTotal: 200, myRemaining: nil,
                                nextSafeActions: actions, pendingPartyUserIDs: ["u2"], myPartyStatus: nil)
        }
        XCTAssertTrue(overlay(requester: true, actions: ["WAIT", "REMIND", "ISSUE_PAYMENT_LINK"]).canIssueLink)
        XCTAssertFalse(overlay(requester: true, actions: ["WAIT", "REMIND"]).canIssueLink)
        XCTAssertFalse(overlay(requester: false, actions: ["ISSUE_PAYMENT_LINK"]).canIssueLink)
    }
}
