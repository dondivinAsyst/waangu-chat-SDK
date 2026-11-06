//
//  FinanceSendMoneyTests.swift
//  FeatureChatTests
//
//  Phase 3 — Send Money de bout en bout sur Chat Core (§3, §9).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceSendMoneyTests: XCTestCase {

    private static let ref = "fco_9c2e"

    // MARK: - §3.1 Bénéficiaire

    func test_resolve_sendsTheMsisdn_andReturnsTheToken_notTheName() async throws {
        let (services, server) = Self.make()
        let recipient = try await services.recipientResolver
            .resolve(.phoneNumber("+25779000111"), knownAs: "Yohana").get()

        XCTAssertEqual(recipient.recipientID, "btk_8f3a", "Le prepare reprend le jeton, jamais le nom")
        XCTAssertEqual(recipient.actor.displayName, "Jean")
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route.hasSuffix("/resolve-beneficiary") })
        XCTAssertEqual(call.body["msisdn"] as? String, "+25779000111")
        XCTAssertEqual(call.body["displayNameHint"] as? String, "Yohana")
    }

    func test_ineligibleBeneficiary_isRefused() async {
        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/resolve-beneficiary"] = FinanceCoreJSON.wrap(
            #"{ "beneficiaryToken": "btk_x", "displayName": "Jean", "eligible": false, "eligibilityReason": "BLOCKED" }"#)
        let (services, _) = Self.make(routes)
        let result = await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil)
        XCTAssertEqual(result.failureValue, .recipientUnresolved(reason: .ineligible))
    }

    // MARK: - §3.2 Prepare

    func test_prepare_usesTheServerCurrency_andOneIdempotencyKey() async throws {
        let (services, server) = Self.make()
        // L'écran passe `CAD` ; le JWT est BI : le serveur impose BIF (§0.3.8).
        let quote = try await services.transferQuoting.quote(for: Self.draft(currency: "CAD")).get()

        XCTAssertEqual(quote.reference.id, Self.ref)
        XCTAssertEqual(quote.totalAmount, 1050)
        XCTAssertEqual(quote.feeAmount, 50)
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route.hasSuffix("/send-money/prepare") })
        XCTAssertEqual(call.body["currency"] as? String, "BIF")
        XCTAssertEqual(call.body["amountMinor"] as? Int64, 1000)
        XCTAssertEqual(call.body["beneficiaryToken"] as? String, "btk_8f3a")
        XCTAssertEqual(call.body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(call.headers["Idempotency-Key"], call.body["idempotencyKey"] as? String)
    }

    func test_complianceHold_neverOpensTheConfirmation() async {
        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/prepare"] = FinanceCoreJSON.wrap(
            #"{ "financialIntentRef": "fco_h", "status": "COMPLIANCE_HOLD", "processRequired": true }"#)
        let (services, _) = Self.make(routes)
        let result = await services.transferQuoting.quote(for: Self.draft())
        XCTAssertEqual(result.failureValue, .complianceBlocked(displayReason: nil))
    }

    // MARK: - §3.3 Execute, par le vrai cas d'usage

    func test_confirm_executesOnce_withThePreparedMaterial_andNeverRefreshesTheQuote() async throws {
        let (services, server) = Self.make()
        let quote = try await services.transferQuoting.quote(for: Self.draft()).get()

        let outcome = await Self.confirm(quote, services: services)

        guard case .executed(let reference) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(reference.id, Self.ref)

        let calls = await server.calls
        let executes = calls.filter { $0.route.hasSuffix("/send-money/execute") }
        XCTAssertEqual(executes.count, 1)
        let body = executes[0].body
        XCTAssertEqual(body["confirmationId"] as? String, "cfp_1")
        XCTAssertEqual(body["quoteId"] as? String, "q_7b")
        XCTAssertEqual(body["objectVersion"] as? String, "v1-a1b2")
        XCTAssertEqual(body["executionPermitId"] as? String, "perm_1")
        XCTAssertEqual(body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(body["deviceId"] as? String, "dev_1")
        XCTAssertFalse(calls.contains { $0.route.contains("quote/refresh") },
                       "Un refresh invaliderait l'empreinte de la confirmation en cours")
        XCTAssertTrue(calls.contains { $0.route == "GET /chat-core/financial/objects/\(Self.ref)" },
                      "Preuve d'écran : la carte")
    }

    /// CF_017 : issue incertaine. Aucun second execute — même si l'on réessaie.
    func test_inDoubtExecute_isNeverRetried() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/execute"] = FinanceCoreJSON.error("CF_017")
        let (services, server) = Self.make(routes)
        let quote = try await services.transferQuoting.quote(for: Self.draft()).get()

        let first = await Self.confirm(quote, services: services)
        let second = await Self.confirm(quote, services: services)

        XCTAssertEqual(first, .failed(.timeoutUnknown))
        XCTAssertNotEqual(second, first, "L'empreinte est consommée : pas de nouvel execute sur la même")
        let executes = await server.calls.filter { $0.route.hasSuffix("/send-money/execute") }
        XCTAssertEqual(executes.count, 1)
    }

    func test_inDoubtStatusInA200_isStillInDoubt() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/execute"] = FinanceCoreJSON.wrap(
            #"{ "financialIntentRef": "fco_9c2e", "status": "IN_DOUBT" }"#)
        let (services, _) = Self.make(routes)
        let quote = try await services.transferQuoting.quote(for: Self.draft()).get()
        let outcome = await Self.confirm(quote, services: services)
        XCTAssertEqual(outcome, .failed(.timeoutUnknown))
    }

    func test_expiredPreparedQuote_isRefused_beforeAnyExecute() async throws {
        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/prepare"] = Self.prepareJSON(expiresAt: "2020-01-01T00:00:00Z")
        let (services, server) = Self.make(routes)
        let quote = try await services.transferQuoting.quote(for: Self.draft()).get()

        let outcome = await Self.confirm(quote, services: services)

        XCTAssertEqual(outcome, .failed(.expired))
        let executes = await server.calls.filter { $0.route.hasSuffix("/execute") }
        XCTAssertTrue(executes.isEmpty)
    }

    /// **Refus serveur = refus définitif.** `CF_074` a refusé l'execute : le
    /// serveur a répondu, donc rien n'a été exécuté. L'écran doit montrer le
    /// refus, aucune carte ne doit partir dans la conversation, et l'inscription
    /// faite juste avant l'appel doit disparaître.
    func test_businessRefusalOnExecute_isDefinitive_andLeavesNothingBehind() async throws {
        FinanceErrorExplanations.shared.clear()
        defer { FinanceErrorExplanations.shared.clear() }

        var routes = Self.routes()
        routes["POST /chat-core/financial/send-money/execute"] = #"""
        { "success": false, "message": null, "statusCode": 0, "data": null,
          "error": { "code": "CF_074",
                     "message": "Conversation membership epoch is stale — resync conversation membership",
                     "details": null },
          "timestamp": "2026-09-17T12:00:01Z" }
        """#
        let (services, server) = Self.make(routes)
        let quote = try await services.transferQuoting.quote(for: Self.draft()).get()
        let store = FinancialObjectStore()
        let objects = FinancialObjectUseCases(
            store: store, client: services.apiClient,
            guardian: services.confirmationGuard,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger())

        let registry = MockIdempotencyPreserver()
        let outcome = await TransferSubmission.confirm(
            quote, recipientID: "btk_8f3a", counterpartyName: "Jean", attestation: nil,
            sendMoney: SendMoneyUseCase(quoting: services.transferQuoting, permits: services.executionPermits,
                                        client: services.apiClient, preserver: registry, logger: SilentLogger()),
            operationKeys: FinanceOperationKeys(preserver: registry),
            objects: objects, deviceID: "dev_1")

        guard case .refused(let error) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(FinanceStrings.errorMessage(error),
                       "Conversation membership epoch is stale — resync conversation membership",
                       "Le message du serveur s'affiche")

        // L'écran : un échec, jamais « en vérification » — donc rien à publier.
        let route = FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference)
        guard case .failed = route else { return XCTFail("\(route)") }

        // Le magasin : aucune trace d'une opération que le serveur a écartée.
        let stored = await store.current(for: quote.reference)
        XCTAssertNil(stored)
        let pending = await objects.pendingReconciliation()
        XCTAssertTrue(pending.isEmpty, "Rien à réconcilier : l'opération n'a pas eu lieu")

        // Un seul execute — un refus ne se rejoue pas — et aucune relecture de
        // carte : il n'y a plus d'objet dont lire la vérité.
        let calls = await server.calls
        XCTAssertEqual(calls.filter { $0.route.hasSuffix("/send-money/execute") }.count, 1)
        XCTAssertTrue(calls.filter { $0.route.contains("/financial/objects/") }.isEmpty)
    }

    /// Une issue **réellement** incertaine garde l'ancien comportement.
    func test_transportFailureOnExecute_staysUncertain() async throws {
        var routes = Self.routes()
        routes.removeValue(forKey: "POST /chat-core/financial/send-money/execute")
        let (services, _) = Self.make(routes)
        let quote = try await services.transferQuoting.quote(for: Self.draft()).get()

        let outcome = await Self.confirm(quote, services: services)

        if case .refused = outcome { XCTFail("Aucune réponse serveur : l'issue reste inconnue") }
    }

    func test_minorUnits_followTheCurrencyExponent() {
        XCTAssertEqual(LiveSendMoney.minorUnits(10.5, currency: "CAD"), 1050)
        XCTAssertEqual(LiveSendMoney.minorUnits(25_000, currency: "BIF"), 25_000)
    }

    // MARK: - Fabriques

    static func make(_ routes: [String: String] = routes()) -> (FinanceCoreLiveServices, ScriptedChatCoreAPIClient) {
        let server = ScriptedChatCoreAPIClient(routes: routes)
        return (FinanceCoreLiveServices(apiClient: server, deviceID: { "dev_1" }), server)
    }

    static func draft(currency: String = "BIF") -> TransferDraft {
        TransferDraft(recipientID: "btk_8f3a", amount: 1000, currency: currency, conversationID: "conv_1")
    }

    static func confirm(_ quote: TransferQuote, services: FinanceCoreLiveServices) async -> SendMoneyUseCase.Outcome {
        let registry = MockIdempotencyPreserver()
        let useCase = SendMoneyUseCase(quoting: services.transferQuoting, permits: services.executionPermits,
                                       client: services.apiClient, preserver: registry, logger: SilentLogger())
        return await TransferSubmission.confirm(
            quote, recipientID: "btk_8f3a", counterpartyName: "Jean", attestation: nil,
            sendMoney: useCase, operationKeys: FinanceOperationKeys(preserver: registry),
            objects: nil, deviceID: "dev_1")
    }

    static func routes() -> [String: String] {
        var routes = FinanceBootstrapTests.routes(resumeLocked: false)
        routes["POST /chat-core/financial/send-money/resolve-beneficiary"] = FinanceCoreJSON.wrap(#"""
        { "beneficiaryToken": "btk_8f3a", "destinationType": "USER_ID", "displayName": "Jean",
          "counterpartyUserId": "usr_jean", "eligible": true, "eligibilityReason": null, "country": "BI",
          "resolvedAt": "2026-09-09T12:00:00Z", "expiresAt": "2099-09-09T12:15:00Z" }
        """#)
        routes["POST /chat-core/financial/send-money/prepare"] = prepareJSON(expiresAt: "2099-09-09T12:02:00Z")
        routes["POST /chat-core/financial/send-money/execute"] = FinanceCoreJSON.wrap(#"""
        { "financialIntentRef": "fco_9c2e", "conversationId": "conv_1", "intentType": "WALLET_TRANSFER",
          "status": "SUBMITTED", "processRequired": false, "executionPermitId": "perm_1",
          "nextSafeActions": ["WAIT"], "message": "Send Money submitted to Finance", "confirmedAt": "2026-09-09T12:01:00Z" }
        """#)
        routes["GET /chat-core/financial/objects/fco_9c2e"] = FinanceCoreJSON.wrap(
            FinanceObjectCardTests.cardJSON(status: "PROCESSING", tone: "PENDING", final: false))
        return routes
    }

    static func prepareJSON(expiresAt: String) -> String {
        FinanceCoreJSON.wrap(#"""
        { "financialIntentRef": "fco_9c2e", "conversationId": "conv_1", "status": "READY_FOR_CONFIRMATION",
          "processRequired": false,
          "beneficiary": { "beneficiaryToken": "btk_8f3a", "displayName": "Jean", "destination": "USER_ID:…a12f",
                           "eligible": true, "expiresAt": "2099-09-09T12:15:00Z" },
          "amountMinor": 1000, "currency": "BIF",
          "quote": { "quoteId": "q_7b", "currency": "BIF", "principalMinor": 1000, "feeMinor": 50,
                     "totalMinor": 1050, "fxRate": null, "fxPair": null, "expiresAt": "\#(expiresAt)" },
          "objectVersion": "v1-a1b2",
          "confirmation": { "confirmationId": "cfp_1", "fingerprint": "fp", "expiresAt": "\#(expiresAt)" },
          "executionPermitId": "perm_1", "complianceCorrelationId": null,
          "message": "Quote prêt — confirmation explicite requise.", "nextSafeActions": ["CONFIRM_SEND", "CANCEL"] }
        """#)
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}
