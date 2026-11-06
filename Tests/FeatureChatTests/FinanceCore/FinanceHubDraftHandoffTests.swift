//
//  FinanceHubDraftHandoffTests.swift
//  FeatureChatTests
//
//  §1.1 négociation, §2.2 brouillon texte, §2.3 handoff.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceHubDraftHandoffTests: XCTestCase {

    // MARK: - §2.2 Brouillon

    /// L'exemple du contrat.
    private static let draft = #"""
    { "actionCode": "SEND_MONEY", "rawText": "envoie 5000 à Jean", "amountMinor": 5000,
      "currency": "BIF", "counterpartyHint": "Jean", "draftOnly": true,
      "message": "Draft only — not a command" }
    """#

    func test_parseRoute_followsTheContract() {
        let endpoint = ChatFinanceEndpoints.parseIntent(.init(text: "envoie 5000 à Jean"))
        XCTAssertEqual(endpoint.path, "/chat-core/financial/hub/intent/parse")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.parameters?["text"] as? String, "envoie 5000 à Jean")
    }

    func test_draft_namesTheActionAndTheAmount_andNothingElse() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/hub/intent/parse"] = FinanceCoreJSON.wrap(Self.draft)
        let (services, server) = FinanceRequestMoneyTests.make(routes)

        let draft = try await services.catalog.draft(from: "  envoie 5000 à Jean ").get()

        XCTAssertEqual(draft.kind, .sendMoney)
        XCTAssertEqual(draft.amount, 5000)
        XCTAssertEqual(draft.counterpartyHint, "Jean")
        let calls = await server.calls
        XCTAssertEqual(calls.first { $0.route.hasSuffix("/intent/parse") }?.body["text"] as? String,
                       "envoie 5000 à Jean")
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/prepare") || $0.route.hasSuffix("/execute") },
                       "Un brouillon ne prépare ni n'exécute rien")
    }

    /// Une lecture de texte présentée comme une commande n'est pas acceptée.
    func test_draftNotMarkedDraftOnly_isRefused() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/hub/intent/parse"] = FinanceCoreJSON.wrap(
            #"{ "actionCode": "SEND_MONEY", "amountMinor": 5000, "currency": "BIF", "draftOnly": false }"#)
        let (services, _) = FinanceRequestMoneyTests.make(routes)

        let result = await services.catalog.draft(from: "envoie 5000 à Jean")

        guard case .failure = result else { return XCTFail("\(result)") }
    }

    func test_unknownAction_leavesNoKind() {
        let dto = IntentDraftDTO(actionCode: "SOMETHING_NEW", rawText: nil, amountMinor: nil,
                                 currency: nil, counterpartyHint: nil, draftOnly: true, message: "x")
        XCTAssertNil(LiveFinanceCatalog.draft(from: dto).kind)
    }

    // MARK: - Boîte à brouillon

    func test_inbox_givesTheDraftOnce_toTheMatchingFlowOnly() async {
        let inbox = FinanceTextDraftInbox()
        let draft = FinanceTextDraft(kind: .sendMoney, amount: 5000, currency: "BIF")

        await inbox.put(draft)
        let wrongFlow = await inbox.take(for: .requestMoney)
        let afterwards = await inbox.take(for: .sendMoney)

        XCTAssertNil(wrongFlow)
        XCTAssertNil(afterwards, "Ouvrir un parcours vide la boîte, même un autre")
    }

    func test_inbox_dropsAStaleDraft() async {
        let inbox = FinanceTextDraftInbox()
        let start = Date()
        await inbox.put(FinanceTextDraft(kind: .sendMoney, amount: 5000, currency: "BIF"), now: start)

        let late = await inbox.take(for: .sendMoney,
                                    now: start.addingTimeInterval(FinanceTextDraftInbox.lifetime + 1))
        XCTAssertNil(late)
    }

    // MARK: - §2.3 Handoff

    func test_handoff_issuesThenConsumes_andReturnsTheServersContext() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/hub/handoff"] = FinanceCoreJSON.wrap(#"""
        { "token": "hnd_1", "expiresAt": "2099-09-09T12:03:00Z",
          "payload": { "userId": "usr_1", "conversationId": "conv_1", "actionCode": "SEND_MONEY",
                       "financialIntentRef": null, "tenantId": "t_1", "country": "BI" } }
        """#)
        routes["POST /chat-core/financial/hub/handoff/consume"] = FinanceCoreJSON.wrap(
            #"{ "userId": "usr_1", "conversationId": "conv_1", "actionCode": "SEND_MONEY", "country": "BI" }"#)
        let (services, server) = FinanceRequestMoneyTests.make(routes)

        XCTAssertTrue(services.catalog.providesHandoff)
        let context = try await services.catalog.handoff(conversationID: "conv_1",
                                                         actionCode: "SEND_MONEY").get()

        XCTAssertEqual(context.conversationID, "conv_1")
        XCTAssertEqual(context.country, "BI")
        let calls = await server.calls.filter { $0.route.contains("/hub/handoff") }
        XCTAssertEqual(calls.map(\.route), ["POST /chat-core/financial/hub/handoff",
                                            "POST /chat-core/financial/hub/handoff/consume"])
        XCTAssertEqual(calls[0].body["actionCode"] as? String, "SEND_MONEY")
        XCTAssertEqual(calls[1].body["token"] as? String, "hnd_1")
    }

    /// `CF_025` : jeton expiré ou rejoué — un refus, pas un contexte.
    func test_expiredHandoff_isAFailure() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/hub/handoff"] = FinanceCoreJSON.wrap(#"{ "token": "hnd_1" }"#)
        routes["POST /chat-core/financial/hub/handoff/consume"] = FinanceCoreJSON.error("CF_025")
        let (services, _) = FinanceRequestMoneyTests.make(routes)

        let result = await services.catalog.handoff(conversationID: "conv_1", actionCode: "SEND_MONEY")
        guard case .failure = result else { return XCTFail("\(result)") }
    }

    /// Rejouer la consommation la ferait échouer alors que la première a pu aboutir.
    func test_consume_isNeverReplayed() {
        XCTAssertFalse(ChatFinanceEndpoints.consumeHandoff(.init(token: "hnd_1")).isIdempotent)
        XCTAssertTrue(ChatFinanceEndpoints.issueHandoff(
            .init(conversationId: "c", actionCode: "SEND_MONEY", financialIntentRef: nil)).isIdempotent)
    }

    /// Les implémentations locales n'ont pas de handoff : le parcours s'ouvre sans.
    func test_closedCatalog_doesNotClaimHandoff() {
        XCTAssertFalse(ClosedChatFinanceCatalog().providesHandoff)
    }

    // MARK: - §1.1 Négociation

    func test_negotiation_sendsWhatTheDeviceKnows_andNeverAGuessedNetworkQuality() async throws {
        let server = ScriptedChatCoreAPIClient(routes: FinanceSendMoneyTests.routes())
        let services = FinanceCoreLiveServices(apiClient: server, deviceID: { "d" },
                                               reducedMotionPreferred: { true })
        _ = await services.session.status()

        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/client-capabilities/negotiate" })
        XCTAssertEqual(call.body["platform"] as? String, "IOS")
        XCTAssertNotNil(call.body["appVersion"] as? String)
        XCTAssertEqual(call.body["reducedMotionPreferred"] as? Bool, true)
        XCTAssertNil(call.body["networkQuality"])
    }
}
