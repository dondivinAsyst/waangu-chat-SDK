//
//  FinanceRequestMoneyTests.swift
//  FeatureChatTests
//
//  Phase 4 — Request Money sur Chat Core (§4).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceRequestMoneyTests: XCTestCase {

    func test_create_sendsTheChatUserID_neverTheBeneficiaryToken() async throws {
        let (services, server) = Self.make()
        _ = try await services.recipientResolver.resolve(.phoneNumber("+25779000111"), knownAs: nil).get()

        let reference = try await services.moneyRequests
            .createRequest(Self.draft(amount: 100), idempotency: FinanceFixtures.idempotency(key: "req-key")).get()

        XCTAssertEqual(reference.type, .moneyRequest)
        XCTAssertEqual(reference.id, "req_1")
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money" })
        XCTAssertEqual(call.body["recipientUserIds"] as? [String], ["usr_jean"])
        XCTAssertEqual(call.body["amountMode"] as? String, "FIXED")
        XCTAssertEqual(call.body["amountMinor"] as? Int64, 100)
        XCTAssertEqual(call.body["currency"] as? String, "BIF", "Devise du serveur")
        XCTAssertEqual(call.body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(call.headers["Idempotency-Key"], "req-key")
        XCTAssertEqual(call.body["idempotencyKey"] as? String, "req-key")
    }

    func test_openAmount_isFreeMode_withoutAmount() async throws {
        let (services, server) = Self.make()
        _ = try await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil).get()
        _ = try await services.moneyRequests.createRequest(Self.draft(amount: nil),
                                                           idempotency: FinanceFixtures.idempotency()).get()
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money" })
        XCTAssertEqual(call.body["amountMode"] as? String, "FREE")
        XCTAssertNil(call.body["amountMinor"])
    }

    /// Sans utilisateur Chat — ni appris du serveur, ni interlocuteur — aucune
    /// demande ne part, et l'échec n'affirme pas que le compte n'existe pas.
    func test_unknownRecipient_sendsNothing() async {
        let (services, server) = Self.make()
        let result = await services.moneyRequests.createRequest(Self.draft(amount: 100),
                                                                idempotency: FinanceFixtures.idempotency())
        guard case .failure(.recipientUnresolved(reason: .undetermined)) = result else {
            return XCTFail("Pas « aucun compte ne correspond » : rien ne le prouve — \(result)")
        }
        let posts = await server.calls.filter { $0.route.hasSuffix("/request-money") }
        XCTAssertTrue(posts.isEmpty)
    }

    /// Résolution réussie sans `counterpartyUserId` : l'interlocuteur de la
    /// conversation devient la partie — c'était l'écran « No account matches ».
    func test_resolutionWithoutChatUser_fallsBackToTheConversationPeer() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/resolve-beneficiary"] = FinanceCoreJSON.wrap(
            #"{ "beneficiaryToken": "btk_8f3a", "displayName": "Jean", "eligible": true }"#)
        let (services, server) = Self.make(routes)
        _ = try await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil).get()

        _ = try await services.moneyRequests.createRequest(Self.draft(amount: 100, peer: "usr_peer"),
                                                           idempotency: FinanceFixtures.idempotency()).get()

        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money" })
        XCTAssertEqual(call.body["recipientUserIds"] as? [String], ["usr_peer"])
    }

    /// Le serveur fait foi : son utilisateur Chat l'emporte sur l'interlocuteur.
    func test_resolvedChatUser_winsOverTheConversationPeer() async throws {
        let (services, server) = Self.make()
        _ = try await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil).get()

        _ = try await services.moneyRequests.createRequest(Self.draft(amount: 100, peer: "usr_peer"),
                                                           idempotency: FinanceFixtures.idempotency()).get()

        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money" })
        XCTAssertEqual(call.body["recipientUserIds"] as? [String], ["usr_jean"])
    }

    func test_remind_namesTheParty() async throws {
        let (services, server) = Self.make()
        _ = try await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil).get()
        let reference = try await services.moneyRequests.createRequest(Self.draft(amount: 100),
                                                                       idempotency: FinanceFixtures.idempotency()).get()

        _ = try await services.moneyRequests.remind(reference, idempotency: FinanceFixtures.idempotency()).get()

        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route.hasSuffix("/request-money/remind") })
        XCTAssertEqual(call.body["requestRef"] as? String, "req_1")
        XCTAssertEqual(call.body["partyUserId"] as? String, "usr_jean")
    }

    func test_remindThrottled_surfacesTheServerRefusal() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/request-money/remind"] = FinanceCoreJSON.error("CF_035")
        let (services, _) = Self.make(routes)
        _ = try await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil).get()
        let reference = try await services.moneyRequests.createRequest(Self.draft(amount: 100),
                                                                       idempotency: FinanceFixtures.idempotency()).get()
        let result = await services.moneyRequests.remind(reference, idempotency: FinanceFixtures.idempotency())
        guard case .failure(.conflict) = result else { return XCTFail("\(result)") }
    }

    func test_revoke_isUnavailable_andSendsNothing() async {
        let (services, server) = Self.make()
        let result = await services.moneyRequests.revoke(FinanceFixtures.reference(type: .moneyRequest, id: "req_1"),
                                                         idempotency: FinanceFixtures.idempotency())
        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - Carte d'une demande

    func test_requestCard_isReadFromRequestMoney_notFromObjects() async {
        let (services, server) = Self.make()
        let store = FinancialObjectStore()
        let useCases = FinancialObjectUseCases(
            store: store, client: services.apiClient, guardian: services.confirmationGuard,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities), logger: SilentLogger())

        _ = await useCases.refresh(FinanceFixtures.reference(type: .moneyRequest, id: "req_1", version: 0))

        let routes = await server.calls.map(\.route)
        XCTAssertTrue(routes.contains("GET /chat-core/financial/request-money/req_1"))
        XCTAssertFalse(routes.contains { $0.contains("/objects/") })
        let payload = await store.current(for: FinanceFixtures.reference(type: .moneyRequest, id: "req_1"))
        XCTAssertEqual(payload?.status, .pending)
        XCTAssertEqual(payload?.amount, 100)
    }

    // MARK: - Fixtures

    static func make(_ routes: [String: String] = routes()) -> (FinanceCoreLiveServices, ScriptedChatCoreAPIClient) {
        let server = ScriptedChatCoreAPIClient(routes: routes)
        return (FinanceCoreLiveServices(apiClient: server, deviceID: { "dev_1" }), server)
    }

    static func draft(amount: Decimal?, peer: String? = nil) -> MoneyRequestDraft {
        MoneyRequestDraft(recipientID: "btk_8f3a", amount: amount, currency: "CAD", conversationID: "conv_1",
                          recipientChatUserID: peer)
    }

    static let requestView = #"""
    { "requestRef": "req_1", "conversationId": "conv_1", "requesterUserId": "usr_me", "status": "OPEN",
      "processRequired": false, "amountMode": "FIXED", "currency": "BIF", "amountMinor": 100,
      "expiresAt": "2099-09-10T12:00:00Z",
      "parties": [ { "chatUserId": "usr_jean", "financialPartyId": "pty_1", "requestedMinor": 100,
                     "paidMinor": 0, "remainingMinor": 100, "currency": "BIF", "status": "PENDING" } ],
      "note": null, "kind": "REQUEST_MONEY", "message": "Payment request created",
      "nextSafeActions": ["PAY", "DECLINE"], "complianceCorrelationId": null }
    """#

    static func routes() -> [String: String] {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/request-money"] = FinanceCoreJSON.wrap(requestView)
        routes["GET /chat-core/financial/request-money/req_1"] = FinanceCoreJSON.wrap(requestView)
        routes["POST /chat-core/financial/request-money/remind"] = FinanceCoreJSON.wrap("{}")
        return routes
    }
}
