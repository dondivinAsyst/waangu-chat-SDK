//
//  FinanceRefreshReceiptDisputeTests.swift
//  FeatureChatTests
//
//  §3.2 refresh d'un devis expiré · Phase 10 reçus et litiges.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceRefreshReceiptDisputeTests: XCTestCase {

    // MARK: - §3.2 Quote refresh

    private static func refreshedJSON() -> String {
        FinanceSendMoneyTests.prepareJSON(expiresAt: "2099-09-09T12:02:00Z")
            .replacingOccurrences(of: "q_7b", with: "q_8c")
            .replacingOccurrences(of: "cfp_1", with: "cfp_2")
            .replacingOccurrences(of: "perm_1", with: "perm_2")
    }

    /// Un devis encore valide se ressert tel quel : un refresh invaliderait
    /// l'empreinte de la confirmation en cours.
    func test_validQuote_isNeverRefreshedOnTheServer() async throws {
        let (services, server) = FinanceSendMoneyTests.make()
        let quote = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()

        let again = try await services.transferQuoting.refreshQuote(quote).get()

        XCTAssertEqual(again, quote)
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/quote/refresh") })
    }

    /// Expiré : nouveau devis sur le **même** FCO, et c'est sa confirmation —
    /// pas l'ancienne — qui part à l'execute.
    func test_expiredQuote_isRefreshed_andTheNewConfirmationIsTheOneExecuted() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/send-money/prepare"] =
            FinanceSendMoneyTests.prepareJSON(expiresAt: "2020-01-01T00:00:00Z")
        routes["POST /chat-core/financial/send-money/quote/refresh"] = Self.refreshedJSON()
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let expired = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()
        XCTAssertTrue(expired.isExpired())

        let fresh = try await services.transferQuoting.refreshQuote(expired).get()
        XCTAssertFalse(fresh.isExpired())
        XCTAssertEqual(fresh.reference.id, expired.reference.id, "Même FCO, pas un nouveau prepare")

        let outcome = await FinanceSendMoneyTests.confirm(fresh, services: services)
        guard case .executed = outcome else { return XCTFail("\(outcome)") }

        let calls = await server.calls
        let refresh = try XCTUnwrap(calls.first { $0.route.hasSuffix("/send-money/quote/refresh") })
        XCTAssertEqual(refresh.body["financialIntentRef"] as? String, "fco_9c2e")
        XCTAssertEqual(refresh.body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(refresh.body["deviceId"] as? String, "dev_1")
        XCTAssertEqual(calls.filter { $0.route.hasSuffix("/send-money/prepare") }.count, 1)
        let execute = try XCTUnwrap(calls.first { $0.route.hasSuffix("/send-money/execute") })
        XCTAssertEqual(execute.body["confirmationId"] as? String, "cfp_2")
        XCTAssertEqual(execute.body["quoteId"] as? String, "q_8c")
    }

    // MARK: - Phase 10 Reçus

    private static let receipt = #"""
    { "receiptRef": "rcpt_1", "financialIntentRef": "fco_9c2e", "conversationId": "conv_1", "sha256": "abc",
      "version": 2, "storageKey": "receipts/fco_9c2e/v2", "classification": "FINANCIAL_RECEIPT",
      "generatedAt": "2026-10-12T10:05:00Z", "signedUrl": "https://finance-docs.example/signed/1",
      "signedUrlExpiresAt": "2099-10-12T10:07:00Z" }
    """#

    private static func services(routes: [String: String],
                                 sequences: [String: [String]] = [:]) -> (FinanceCoreLiveServices, ScriptedChatCoreAPIClient) {
        let server = ScriptedChatCoreAPIClient(routes: routes, sequences: sequences)
        return (FinanceCoreLiveServices(apiClient: server, deviceID: { "dev_1" }), server)
    }

    private static let paymentRef = FinanceFixtures.reference(type: .payment, id: "fco_9c2e", version: 1)

    func test_receipt_isTheFinanceSignedURL() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/receipts/share"] = FinanceCoreJSON.wrap(Self.receipt)
        let (services, server) = Self.services(routes: routes)

        let signed = try await services.receipts.receipt(for: Self.paymentRef, variant: .final).get()

        XCTAssertEqual(signed.url.absoluteString, "https://finance-docs.example/signed/1")
        XCTAssertEqual(signed.documentHash, "abc")
        XCTAssertEqual(signed.version, 2)
        XCTAssertEqual(signed.variant, .final)
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/receipts/issue") })
    }

    /// Pas encore émis : émis, puis l'URL redemandée.
    func test_receiptNotYetIssued_isIssuedThenShared() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/receipts/issue"] = FinanceCoreJSON.wrap(
            Self.receipt.replacingOccurrences(of: "\"https://finance-docs.example/signed/1\"", with: "null"))
        let (services, server) = Self.services(
            routes: routes,
            sequences: ["POST /chat-core/financial/receipts/share": [FinanceCoreJSON.error("CF_011"),
                                                                    FinanceCoreJSON.wrap(Self.receipt)]])

        let signed = try await services.receipts.receipt(for: Self.paymentRef, variant: .final).get()

        XCTAssertEqual(signed.receiptID, "rcpt_1")
        let routesHit = await server.calls.map(\.route).filter { $0.contains("/receipts/") }
        XCTAssertEqual(routesHit, ["POST /chat-core/financial/receipts/share",
                                   "POST /chat-core/financial/receipts/issue",
                                   "POST /chat-core/financial/receipts/share"])
    }

    /// Finance non câblé : émettre n'y changerait rien.
    func test_financeNotWired_doesNotIssue() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/receipts/share"] = FinanceCoreJSON.error("CF_051")
        let (services, server) = Self.services(routes: routes)

        let result = await services.receipts.receipt(for: Self.paymentRef, variant: .final)

        guard case .failure = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/receipts/issue") })
    }

    /// Un reçu provisoire dirait « payé » trop tôt : rien n'est demandé.
    func test_provisionalReceipt_isNeverRequested() async {
        let (services, server) = Self.services(routes: FinanceSendMoneyTests.routes())

        let result = await services.receipts.receipt(for: Self.paymentRef, variant: .provisional)

        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.contains("/receipts/") })
    }

    // MARK: - Phase 10 Litiges

    private static let taxonomy = #"""
    ["UNRECOGNIZED_PAYMENT","WRONG_BENEFICIARY","CASH_RECEIVED_NOT_CREDITED","CASHOUT_NOT_REMITTED",
     "SERVICE_NOT_DELIVERED","DOUBLE_DEBIT","BILLER_NOT_UPDATED","TOPUP_NOT_DELIVERED",
     "REFUND_NOT_RECEIVED","QR_FRAUD","OTHER"]
    """#

    private static let disputeCase = #"""
    { "disputeId": "dsp_1", "conversationId": "conv_1", "supportConversationId": "fin-sup-1",
      "financialIntentRef": "fco_9c2e", "category": "WRONG_BENEFICIARY", "priority": "HIGH", "status": "OPEN",
      "evidence": [] }
    """#

    private static func disputeRoutes() -> [String: String] {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/financial/disputes/taxonomy"] = FinanceCoreJSON.wrap(Self.taxonomy)
        routes["POST /chat-core/financial/disputes"] = FinanceCoreJSON.wrap(Self.disputeCase)
        routes["POST /chat-core/financial/disputes/dsp_1/evidence"] = FinanceCoreJSON.wrap(Self.disputeCase)
        return routes
    }

    private static func draft(_ reason: DisputeReason, consent: Bool = true,
                              description: String = "Pas reçu") -> DisputeDraft {
        DisputeDraft(reference: paymentRef, reason: reason, description: description,
                     correlationID: paymentRef.correlationID, observedStatus: .completed,
                     conversationID: "conv_1", sharingConsent: consent)
    }

    func test_dispute_opensWithTheServersCategory_thenAttachesTheDescription() async throws {
        let (services, server) = Self.services(routes: Self.disputeRoutes())

        let reference = try await services.disputes.file(
            Self.draft(.wrongRecipient), idempotency: IdempotencyContext.new(deviceID: "dev_1")).get()

        XCTAssertEqual(reference.id, "dsp_1")
        XCTAssertEqual(reference.type, .dispute)
        let calls = await server.calls
        let open = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/disputes" })
        XCTAssertEqual(open.body["category"] as? String, "WRONG_BENEFICIARY")
        XCTAssertEqual(open.body["financialIntentRef"] as? String, "fco_9c2e")
        XCTAssertNil(open.body["priority"], "La priorité appartient au serveur")
        let note = try XCTUnwrap(calls.first { $0.route.hasSuffix("/disputes/dsp_1/evidence") })
        XCTAssertEqual(note.body["type"] as? String, "NOTE")
        XCTAssertEqual(note.body["content"] as? String, "Pas reçu")
    }

    /// Le client ne décide pas de la priorité, même pour une fraude.
    func test_fraud_sendsNoPriority() async throws {
        let (services, server) = Self.services(routes: Self.disputeRoutes())
        _ = try await services.disputes.file(Self.draft(.fraud),
                                             idempotency: IdempotencyContext.new(deviceID: "dev_1")).get()
        let calls = await server.calls
        let open = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/disputes" })
        XCTAssertNil(open.body["priority"])
        XCTAssertEqual(open.body["category"] as? String, "UNRECOGNIZED_PAYMENT")
    }

    /// Jamais une catégorie que le serveur ne liste pas (`CF_048`).
    func test_categoryOutsideTheTaxonomy_becomesOther() {
        XCTAssertEqual(LiveDisputeFiling.category(for: .billIssue, objectType: .bill, in: ["OTHER"]), "OTHER")
        XCTAssertEqual(LiveDisputeFiling.category(for: .cashIssue, objectType: .cashOut,
                                                  in: ["CASHOUT_NOT_REMITTED", "OTHER"]), "CASHOUT_NOT_REMITTED")
    }

    func test_withoutConsent_nothingIsSent() async {
        let (services, server) = Self.services(routes: Self.disputeRoutes())
        let result = await services.disputes.file(Self.draft(.wrongRecipient, consent: false),
                                                  idempotency: IdempotencyContext.new(deviceID: "dev_1"))
        guard case .failure = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.contains("/disputes") })
    }

    /// Le litige existe : une note refusée ne le fait pas rouvrir.
    func test_noteFailure_stillReportsTheOpenedDispute() async throws {
        var routes = Self.disputeRoutes()
        routes["POST /chat-core/financial/disputes/dsp_1/evidence"] = FinanceCoreJSON.error("CF_049")
        let (services, _) = Self.services(routes: routes)
        let reference = try await services.disputes.file(Self.draft(.wrongRecipient),
                                                         idempotency: IdempotencyContext.new(deviceID: "dev_1")).get()
        XCTAssertEqual(reference.id, "dsp_1")
    }

    // MARK: - §12 Capacité périmée : refresh puis une seconde tentative

    /// `CF_012` sur un prepare : capacité relue, prepare rejoué **une** fois,
    /// sous la même clé — même clé et même corps, donc la même intention.
    func test_staleCapability_refreshesThenRetriesOnce() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/capability/refresh"] = FinanceCoreJSON.wrap(
            #"{ "key": "BI:WALLET_TRANSFER", "availability": "AVAILABLE" }"#)
        let (services, server) = Self.services(
            routes: routes,
            sequences: ["POST /chat-core/financial/send-money/prepare": [
                FinanceCoreJSON.error("CF_012"),
                FinanceSendMoneyTests.prepareJSON(expiresAt: "2099-09-09T12:02:00Z")]])

        _ = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()

        let calls = await server.calls.filter { $0.route.contains("/prepare") || $0.route.contains("/capability/refresh") }
        XCTAssertEqual(calls.map(\.route), ["POST /chat-core/financial/send-money/prepare",
                                            "POST /chat-core/financial/capability/refresh",
                                            "POST /chat-core/financial/send-money/prepare"])
        XCTAssertEqual(calls[0].body["idempotencyKey"] as? String, calls[2].body["idempotencyKey"] as? String)
    }

    /// **Jamais pour un execute** : le rejouer est l'interdit du §0.3.3.
    func test_staleCapabilityOnExecute_isNeverRetried() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/send-money/execute"] = FinanceCoreJSON.error("CF_012")
        routes["POST /chat-core/financial/capability/refresh"] = FinanceCoreJSON.wrap(#"{ "key": "k" }"#)
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let quote = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()

        _ = await FinanceSendMoneyTests.confirm(quote, services: services)

        let calls = await server.calls
        XCTAssertEqual(calls.filter { $0.route.hasSuffix("/send-money/execute") }.count, 1)
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/capability/refresh") })
    }

    // MARK: - Phase 10 Annulation

    func test_cancelBeforeSubmission_isCancelled() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/intent/cancel-request"] = FinanceCoreJSON.wrap(
            #"{ "financialIntentRef": "fco_9c2e", "status": "CANCELLED", "cancelRequested": true }"#)
        let (services, server) = Self.services(routes: routes)

        let outcome = try await services.apiClient.cancelIntent(Self.paymentRef, conversationID: "conv_1")

        XCTAssertEqual(outcome, .cancelled)
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route.hasSuffix("/intent/cancel-request") })
        XCTAssertEqual(call.body["financialIntentRef"] as? String, "fco_9c2e")
        XCTAssertEqual(call.body["conversationId"] as? String, "conv_1")
        XCTAssertNotNil(call.body["reason"] as? String)
    }

    /// `CF_046` : demandée, pas faite — jamais rapporté comme annulé.
    func test_cancelAfterSubmission_isOnlyRequested() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/intent/cancel-request"] = FinanceCoreJSON.error("CF_046")
        let (services, _) = Self.services(routes: routes)

        let outcome = try await services.apiClient.cancelIntent(Self.paymentRef, conversationID: nil)

        XCTAssertEqual(outcome, .requested)
    }

    /// Les actions permises par le serveur suivent la carte jusqu'à l'écran.
    func test_allowedActions_travelWithTheCard() throws {
        let card = try JSONDecoder().decode(
            FcoClientCardDTO.self,
            from: Data(FinanceObjectCardTests.cardJSON(status: "PROCESSING", tone: "PENDING", final: false).utf8))
        XCTAssertEqual(FcoCardMapper.envelope(from: card).metadata["allowedActions"], "WAIT")
    }

    // MARK: - Phase 8 Traduction

    func test_translation_restoresTheServersProtectedValues() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/hub/translation/mask"] = FinanceCoreJSON.wrap(#"""
        { "original": "x", "masked": "Envoie {{AMT_1}} à {{MSISDN_1}}",
          "tokens": { "{{AMT_1}}": "5000 BIF", "{{MSISDN_1}}": "+25779000000" } }
        """#)
        routes["POST /chat-core/financial/hub/translation/translate"] = FinanceCoreJSON.wrap(
            #""Send {{AMT_1}} to {{MSISDN_1}} for the dinner yesterday""#)
        let (services, server) = Self.services(routes: routes)
        let protected = ProtectedText.protect(
            "Envoie 5000 BIF à +25779000000 pour le dîner d'hier soir avec les amis", segments: [])

        let translated = try await services.translator.translate(protected, to: "en", glossaryVersion: nil).get()

        XCTAssertEqual(translated.text, "Send 5000 BIF to +25779000000 for the dinner yesterday")
        XCTAssertEqual(translated.authority, .machine)
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route.hasSuffix("/translation/translate") })
        XCTAssertEqual(call.body["sourceLang"] as? String, "fr")
        XCTAssertEqual(call.body["targetLang"] as? String, "en")
    }

    /// Un jeton perdu, c'est une valeur que le traducteur a touchée : refusé.
    func test_translationThatLostAProtectedValue_isRefused() {
        XCTAssertNil(LiveFinancialTranslator.restore("Send to {{MSISDN_1}}",
                                                     tokens: ["{{AMT_1}}": "5000 BIF", "{{MSISDN_1}}": "+257"]))
    }

    /// Moteur absent (`CF_063`) : un échec, jamais un texte inventé.
    func test_translationEngineNotWired_isAFailure() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/hub/translation/mask"] = FinanceCoreJSON.error("CF_063")
        let (services, _) = Self.services(routes: routes)
        let protected = ProtectedText.protect("Envoie l'argent pour le dîner d'hier soir avec les amis", segments: [])

        let result = await services.translator.translate(protected, to: "en", glossaryVersion: nil)

        guard case .failure = result else { return XCTFail("\(result)") }
    }

    // MARK: - §5.2 Facture marchande

    private static let outstanding = #"""
    { "invoiceRef": "inv_1", "merchantId": "m_1", "storeId": "s_1", "terminalId": null,
      "outstandingMinor": 12000, "paidMinor": 0, "currency": "BIF", "status": "OPEN",
      "expiresAt": "2099-09-10T00:00:00Z" }
    """#

    private static let quotedPrepare = #"""
    {"financialIntentRef":"fco_inv_1","conversationId":"conv_1","status":"READY_FOR_CONFIRMATION",
     "processRequired":false,"amountMinor":12000,"currency":"BIF","quoteId":"q_1","feeMinor":0,
     "totalMinor":12000,"fxRate":null,"quoteExpiresAt":"2099-09-09T12:02:00Z","objectVersion":"v1-x",
     "confirmation":{"confirmationId":"cfp_1","fingerprint":"f","expiresAt":"2099-09-09T12:02:00Z"},
     "merchantId":"m_1","executionPermitId":"perm_1","message":"ok","nextSafeActions":["CONFIRM","CANCEL"]}
    """#

    /// Ce que le serveur ne rend pas reste vide : pas de total recomposé.
    func test_invoice_showsOnlyWhatTheMerchantBackendSaid() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/invoice/inquire"] = FinanceCoreJSON.wrap(Self.outstanding)
        let (services, server) = Self.services(routes: routes)

        let invoice = try await services.merchantInvoices.invoice(id: "inv_1").get()

        XCTAssertEqual(invoice.amountDue.minorUnits, 12000)
        XCTAssertEqual(invoice.merchantID, "m_1")
        XCTAssertEqual(invoice.state, .issued)
        XCTAssertNil(invoice.total)
        XCTAssertNil(invoice.subtotal)
        XCTAssertTrue(invoice.lines.isEmpty)
        XCTAssertFalse(invoice.allowsPartialPayment)
        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route.hasSuffix("/invoice/inquire") })
        XCTAssertEqual(call.body["invoiceRef"] as? String, "inv_1")
        XCTAssertNil(call.body["merchantId"], "Jamais un merchantId inventé")
    }

    /// Le reste dû a bougé entre la lecture et le paiement : on relit.
    func test_invoiceWhoseAmountChanged_isMutated() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/invoice/inquire"] = FinanceCoreJSON.wrap(
            Self.outstanding.replacingOccurrences(of: "12000", with: "15000"))
        let (services, _) = Self.services(routes: routes)
        let shown = LiveInvoiceProvider.invoice(from: try JSONDecoder().decode(
            InvoiceOutstandingDTO.self, from: Data(Self.outstanding.utf8)))

        let verdict = try await services.merchantInvoices.revalidate(shown.snapshot()).get()

        guard case .mutated(.amountChanged, _) = verdict else { return XCTFail("\(verdict)") }
    }

    func test_paidInvoice_isNotPayable() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/invoice/inquire"] = FinanceCoreJSON.wrap(
            Self.outstanding.replacingOccurrences(of: "\"OPEN\"", with: "\"PAID\""))
        let (services, _) = Self.services(routes: routes)
        let shown = LiveInvoiceProvider.invoice(from: try JSONDecoder().decode(
            InvoiceOutstandingDTO.self, from: Data(Self.outstanding.utf8)))

        let verdict = try await services.merchantInvoices.revalidate(shown.snapshot()).get()

        guard case .cancelled = verdict else { return XCTFail("\(verdict)") }
    }

    /// Un devis, jamais un débit — et pas de montant envoyé : c'est celui du serveur.
    func test_invoicePayment_isAQuoteOnTheServersAmount() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/invoice/prepare"] = FinanceCoreJSON.wrap(Self.quotedPrepare)
        let (services, server) = Self.services(routes: routes)
        let invoice = LiveInvoiceProvider.invoice(from: try JSONDecoder().decode(
            InvoiceOutstandingDTO.self, from: Data(Self.outstanding.utf8)))

        XCTAssertTrue(services.merchantInvoices.providesQuotes)
        let quote = try await services.merchantInvoices.quote(
            invoice, conversationID: "conv_1", idempotency: IdempotencyContext.new(deviceID: "dev_1")).get()

        XCTAssertEqual(quote.reference.id, "fco_inv_1")
        let calls = await server.calls
        let prepare = try XCTUnwrap(calls.first { $0.route.hasSuffix("/invoice/prepare") })
        XCTAssertEqual(prepare.body["invoiceRef"] as? String, "inv_1")
        XCTAssertEqual(prepare.body["merchantId"] as? String, "m_1")
        XCTAssertNil(prepare.body["amountMinor"])
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") })

        let direct = await services.merchantInvoices.pay(
            invoiceID: "inv_1", snapshot: invoice.snapshot(), allocation: .full,
            idempotency: IdempotencyContext.new(deviceID: "dev_1"), stepUp: nil)
        guard case .failure(.capabilityUnavailable) = direct else { return XCTFail("\(direct)") }
    }
}

