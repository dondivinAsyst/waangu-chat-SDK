//
//  FinanceTopUpTests.swift
//  FeatureChatTests
//
//  §5.3 — recharge : catalogue, numéro résolu par le serveur, devis, overlay.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceTopUpTests: XCTestCase {

    // MARK: - Routes

    func test_routes_followTheContract() {
        XCTAssertEqual(QuotedOperation.topUp.prepareRoute, "/financial/top-up/prepare")
        XCTAssertEqual(QuotedOperation.topUp.executeRoute, "/financial/top-up/execute")
        XCTAssertEqual(ChatFinanceEndpoints.topUpCatalogue(country: "BI").path,
                       "/chat-core/financial/top-up/catalogue")
        XCTAssertEqual(ChatFinanceEndpoints.topUpCatalogue(country: "BI").parameters as? [String: String],
                       ["country": "BI"])
        XCTAssertEqual(ChatFinanceEndpoints.resolveMsisdn(.init(msisdn: "+25779000000")).path,
                       "/chat-core/financial/top-up/resolve-msisdn")
        XCTAssertEqual(ChatFinanceEndpoints.topUpRequery(.init(financialIntentRef: "fco_1",
                                                              conversationId: nil)).path,
                       "/chat-core/financial/top-up/requery")
    }

    /// `/top-up/delivery` est refusé par le serveur (`CF_054`) : aucune route ne
    /// l'atteint, et rien ne doit l'ajouter par symétrie avec les autres.
    func test_deliveryRoute_isNotReachable() {
        let routes = [ChatFinanceEndpoints.topUpCatalogue(country: nil).path,
                      ChatFinanceEndpoints.resolveMsisdn(.init(msisdn: "x")).path,
                      ChatFinanceEndpoints.topUpRequery(.init(financialIntentRef: "r",
                                                             conversationId: nil)).path]
        XCTAssertFalse(routes.contains { $0.hasSuffix("/top-up/delivery") })
    }

    // MARK: - Catalogue

    /// Forme publiée au §5.3.1.
    private static let catalogue = #"""
    [{"code":"AIRTIME_1000","label":"Airtime 1000","kind":"AIRTIME","country":"BI","amountMinor":1000,"currency":"BIF","billerId":"STUB_TELCO","status":"ACTIVE"},{"code":"DATA_500MB","label":"Data 500 Mo","kind":"DATA","country":"BI","amountMinor":2500,"currency":"BIF","billerId":"STUB_TELCO","status":"ACTIVE"}]
    """#

    private func entries(_ json: String = catalogue) throws -> [TopUpProductDTO] {
        try JSONDecoder().decode([TopUpProductDTO].self, from: Data(json.utf8))
    }

    func test_catalogue_becomesProducts_inServerOrder() throws {
        let products = LiveTopUp.products(from: try entries(), operatorName: "LUMITEL")

        XCTAssertEqual(products.map(\.id), ["AIRTIME_1000", "DATA_500MB"])
        XCTAssertEqual(products.map(\.kind), [.airtime, .data])
        XCTAssertEqual(products.first?.amount, 1000, "BIF n'a pas de décimales")
        XCTAssertEqual(products.first?.currency, "BIF")
        XCTAssertEqual(products.first?.labelKey, "Airtime 1000")
        XCTAssertEqual(products.map(\.operatorName), ["LUMITEL", "LUMITEL"],
                       "L'opérateur vient de la résolution du numéro, pas du produit")
    }

    /// **La réponse réelle du backend (06/10).** Le contrat publie
    /// `"kind": "AIRTIME"` ; le serveur rend `TOPUP`, et sert tout le Biller
    /// Hub sur la même route — bouquet TV, scolarité, impôt compris.
    private static let realCatalogue = #"""
    [{"code":"STUB_AIRTIME_500","label":"Airtime 500 (stub)","kind":"TOPUP","country":"BURUNDI","amountMinor":500,"currency":"BIF","billerId":"STUB_TV","status":"ACTIVE"},{"code":"STUB_DATA_1GB","label":"Data 1GB (stub)","kind":"TOPUP","country":"BURUNDI","amountMinor":2000,"currency":"BIF","billerId":"STUB_TV","status":"ACTIVE"},{"code":"STUB_TV_MONTH","label":"Bouquet mois (stub)","kind":"SUBSCRIPTION","country":"BURUNDI","amountMinor":15000,"currency":"BIF","billerId":"STUB_TV","status":"ACTIVE"},{"code":"STUB_SCHOOL_T1","label":"Trimestre 1 (stub)","kind":"FEES","country":"BURUNDI","amountMinor":75000,"currency":"BIF","billerId":"STUB_SCHOOL","status":"ACTIVE"},{"code":"STUB_TAX_IRPP","label":"IRPP (stub)","kind":"TAX","country":"BURUNDI","amountMinor":50000,"currency":"BIF","billerId":"STUB_DGI_TAX","status":"ACTIVE"}]
    """#

    /// Le défaut qui vidait l'écran : `TopUpKind(rawValue:)` ne connaissait pas
    /// `TOPUP`, les cinq produits tombaient, et l'écran disait seulement
    /// « aucun forfait ».
    func test_realCatalogue_isServedAsTheServerSendsIt() throws {
        let products = LiveTopUp.products(from: try entries(Self.realCatalogue),
                                          operatorName: "STUB_OP")

        XCTAssertEqual(products.map(\.id),
                       ["STUB_AIRTIME_500", "STUB_DATA_1GB", "STUB_TV_MONTH",
                        "STUB_SCHOOL_T1", "STUB_TAX_IRPP"],
                       "Le catalogue est la décision du serveur — le client n'en retire rien")
        XCTAssertEqual(products.map(\.labelKey).first, "Airtime 500 (stub)",
                       "Le libellé vient du serveur")
        XCTAssertEqual(products.first?.amount, 500)
        XCTAssertEqual(products.map(\.operatorName).first, "STUB_OP")
    }

    /// Une catégorie que ce client ne nomme pas n'est pas une raison de cacher
    /// le produit : elle le prive seulement d'un intitulé de section.
    func test_unknownCategory_isOffered_withoutAFabricatedNature() {
        XCTAssertEqual(LiveTopUp.kind(of: "SUBSCRIPTION"), .unspecified)
        XCTAssertEqual(LiveTopUp.kind(of: "FEES"), .unspecified)
        XCTAssertEqual(LiveTopUp.kind(of: "TAX"), .unspecified)
        XCTAssertEqual(LiveTopUp.kind(of: "TOPUP"), .unspecified)
        XCTAssertEqual(LiveTopUp.kind(of: nil), .unspecified)
    }

    /// Le vocabulaire que le contrat publie reste reconnu : le jour où le
    /// serveur l'enverra, les sections par nature reviennent d'elles-mêmes.
    func test_contractVocabulary_isStillRecognised() {
        XCTAssertEqual(LiveTopUp.kind(of: "AIRTIME"), .airtime)
        XCTAssertEqual(LiveTopUp.kind(of: "DATA"), .data)
        XCTAssertEqual(LiveTopUp.kind(of: "bundle"), .bundle)
    }

    func test_inactiveProduct_isNotOffered() throws {
        let json = #"[{"code":"A","kind":"AIRTIME","amountMinor":1,"currency":"BIF","status":"SUSPENDED"},{"code":"B","kind":"AIRTIME","amountMinor":1,"currency":"BIF","status":"ACTIVE"}]"#
        XCTAssertEqual(LiveTopUp.products(from: try entries(json), operatorName: "").map(\.id), ["B"])
    }

    /// Un produit dont la catégorie est inconnue reste proposé : c'est le
    /// serveur qui décide de ce qu'il offre, pas la liste de ce client.
    func test_unknownKind_isStillOffered() throws {
        let json = #"[{"code":"A","kind":"SATELLITE_MINUTES","amountMinor":1,"currency":"BIF","status":"ACTIVE"}]"#
        let products = LiveTopUp.products(from: try entries(json), operatorName: "")
        XCTAssertEqual(products.map(\.id), ["A"])
        XCTAssertEqual(products.first?.kind, .unspecified)
    }

    func test_productWithoutAmountOrCurrency_promisesNothing() throws {
        let json = #"[{"code":"A","kind":"AIRTIME","currency":"BIF","status":"ACTIVE"},{"code":"B","kind":"AIRTIME","amountMinor":1000,"status":"ACTIVE"}]"#
        XCTAssertTrue(LiveTopUp.products(from: try entries(json), operatorName: "").isEmpty)
    }

    func test_missingLabel_fallsBackToTheCode_neverToAFabricatedName() throws {
        let json = #"[{"code":"AIRTIME_1000","kind":"AIRTIME","amountMinor":1000,"currency":"BIF","status":"ACTIVE"}]"#
        XCTAssertEqual(LiveTopUp.products(from: try entries(json), operatorName: "").first?.labelKey,
                       "AIRTIME_1000")
    }

    // MARK: - Numéro résolu

    /// Forme publiée au §5.3.1 : l'indice d'opérateur se dit non autoritatif
    /// dans la réponse elle-même.
    func test_resolvedMsisdn_carriesItsOwnPortabilityWarning() throws {
        let json = #"""
        {"msisdnNormalized":"25779000000","msisdnMasked":"****0000","operatorHint":"LUMITEL","authoritative":false,"portabilityWarning":"Prefix is a hint — not absolute portability truth"}
        """#
        let dto = try JSONDecoder().decode(ResolvedMsisdnDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.msisdnNormalized, "25779000000")
        XCTAssertEqual(dto.operatorHint, "LUMITEL")
        XCTAssertEqual(dto.authoritative, false)
        XCTAssertNotNil(dto.portabilityWarning)
    }

    /// Le prepare part sur le numéro **normalisé par le serveur**, pas sur la
    /// saisie qu'il venait de corriger.
    func test_normalizedNumber_isRememberedForThePrepare() async throws {
        let memo = TopUpResolutionMemo()
        let json = #"{"msisdnNormalized":"25779000000","msisdnMasked":"****0000"}"#
        let dto = try JSONDecoder().decode(ResolvedMsisdnDTO.self, from: Data(json.utf8))
        await memo.remember(dto, for: "+257 79 000 000")

        let normalized = await memo.normalized(for: "+257 79 000 000")
        XCTAssertEqual(normalized, "25779000000")
        let unknown = await memo.normalized(for: "+25779000001")
        XCTAssertNil(unknown, "Jamais de numéro deviné pour une saisie non résolue")
    }

    // MARK: - Overlay

    /// Forme publiée au §5.3.1 : sept statuts, et pas un seul « terminé ».
    private static let overlay = #"""
    {"financialIntentRef":"fco_t1","conversationId":"conv_1","msisdnMasked":"****0000","msisdnHash":"h","productCode":"AIRTIME_1000","snapshotId":"snap_1","snapshotHash":"sh","inquiryStatus":"OK","quoteStatus":"CONSUMED","paymentStatus":"SUBMITTED","settlementStatus":"PENDING","deliveryStatus":null,"fulfillmentStatus":"PENDING","reconciliationStatus":null,"tokenPresent":false,"bulkId":null,"recurringMandateRef":null,"bulkLineRefs":[]}
    """#

    private func overlay(_ json: String = overlay) throws -> TopUpOverlayDTO {
        try JSONDecoder().decode(TopUpOverlayDTO.self, from: Data(json.utf8))
    }

    /// `SUBMITTED` n'est pas un `PaymentStatus` : décodé par valeur brute il
    /// tombait sur `unknown`, c'est-à-dire « on ne sait pas » d'une recharge
    /// dont on sait très bien qu'elle est partie.
    func test_submittedPayment_isInFlight_notUnknown() throws {
        let status = LiveTopUp.status(of: try overlay())
        XCTAssertEqual(status, .queued)
        XCTAssertTrue(status.isInFlight)
    }

    /// **Le cas qui compte.** Débit réglé, crédit télécom non livré : ce n'est
    /// pas un succès — c'est le `TOPUP_NOT_DELIVERED` des litiges.
    func test_settledPaymentWithoutDelivery_isNotASuccess() throws {
        let json = #"{"financialIntentRef":"fco_t1","paymentStatus":"SETTLED","fulfillmentStatus":"PENDING","deliveryStatus":"NOT_STARTED"}"#
        let status = LiveTopUp.status(of: try overlay(json))
        XCTAssertEqual(status, .pendingReconciliation)
        XCTAssertNotEqual(status, .completed)
    }

    func test_deliveredTopUp_isASuccess() throws {
        let json = #"{"financialIntentRef":"fco_t1","paymentStatus":"COMPLETED","fulfillmentStatus":"DELIVERED"}"#
        XCTAssertEqual(LiveTopUp.status(of: try overlay(json)), .completed)
    }

    /// Une valeur de livraison que ce client ne connaît pas n'est pas une
    /// livraison. L'inverse afficherait « rechargé » sur un mot deviné.
    func test_unknownFulfillmentWord_isNeverReadAsDelivered() throws {
        let json = #"{"financialIntentRef":"fco_t1","paymentStatus":"COMPLETED","fulfillmentStatus":"HANDED_TO_PARTNER"}"#
        XCTAssertEqual(LiveTopUp.status(of: try overlay(json)), .pendingReconciliation)
    }

    func test_failedPayment_staysFailed_whateverTheDelivery() throws {
        let json = #"{"financialIntentRef":"fco_t1","paymentStatus":"FAILED","fulfillmentStatus":"DELIVERED"}"#
        XCTAssertEqual(LiveTopUp.status(of: try overlay(json)), .failed)
    }

    /// `/bulk` n'est pas ouvert : des références de lot ne fabriquent pas des
    /// lignes de résultat dont aucun statut ne serait vrai.
    func test_overlay_becomesOneLine_evenWithBulkRefs() throws {
        let json = #"{"financialIntentRef":"fco_t1","msisdnMasked":"****0000","paymentStatus":"SUBMITTED","bulkLineRefs":["fco_a","fco_b"]}"#
        let reference = FinancialReference(type: .airtime, id: "fco_t1", version: 0,
                                           correlationID: CorrelationId())
        let order = LiveTopUp.order(from: try overlay(json), reference: reference)

        XCTAssertEqual(order.results.count, 1)
        XCTAssertEqual(order.results.first?.msisdn, "****0000", "Masqué, tel que rendu")
        XCTAssertEqual(order.aggregate, .inFlight)
    }

    // MARK: - Vocabulaire partagé

    /// La carte et l'overlay lisent la **même** liste de mots. Une divergence
    /// ferait dire deux choses d'une même opération selon l'écran.
    func test_cardAndOverlay_shareTheSameVocabulary() {
        for word in ["SUBMITTED", "PROCESSING", "RISK_CHECKING", "SENT_TO_SWITCH",
                     "ACCEPTED", "RECONCILIATION_REQUIRED", "COMPLIANCE_HOLD",
                     "IN_DOUBT", "FAILED", "REJECTED", "REVERSED"] {
            let fromOverlay = LiveTopUp.status(of: TopUpOverlayDTO(
                financialIntentRef: "r", conversationId: nil, msisdnMasked: nil, msisdnHash: nil,
                productCode: nil, snapshotId: nil, snapshotHash: nil, inquiryStatus: nil,
                quoteStatus: nil, paymentStatus: word, settlementStatus: nil, deliveryStatus: nil,
                fulfillmentStatus: nil, reconciliationStatus: nil, tokenPresent: nil,
                bulkId: nil, recurringMandateRef: nil, bulkLineRefs: nil))
            XCTAssertEqual(fromOverlay, FcoCardMapper.paymentStatus(word), word)
        }
    }

    /// Un mot que personne ne connaît reste `unknown` — jamais `failed`, qui
    /// inviterait à recharger une ligne peut-être déjà créditée.
    func test_unknownPaymentWord_isUnknown_neverFailed() throws {
        let json = #"{"financialIntentRef":"fco_t1","paymentStatus":"SOMETHING_NEW"}"#
        XCTAssertEqual(LiveTopUp.status(of: try overlay(json)), .unknown)
    }

    // MARK: - Devis

    /// Le contrat prépare, fait confirmer, puis exécute. Un ordre direct
    /// rechargerait sans que personne ait confirmé.
    func test_directOrder_isRefused_andQuotesAreAnnounced() async {
        let (services, _) = FinanceQuotedOperationsTests.make()
        let topUp = services.topUp
        XCTAssertTrue(topUp.providesQuotes)

        let request = TopUpOrderRequest(lines: [TopUpLine(msisdn: "+25779000000",
                                                          productID: "AIRTIME_1000")],
                                        conversationID: "conv_1")
        let result = await topUp.order(request, idempotency: FinanceFixtures.idempotency())
        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
    }

    /// `/bulk` rend un FCO **par ligne**, chacun avec sa confirmation : un
    /// devis unique ne les représente pas, et n'est donc pas demandé.
    func test_multiLineOrder_doesNotAskForASingleQuote() async {
        let (services, server) = FinanceQuotedOperationsTests.make()
        let request = TopUpOrderRequest(
            lines: [TopUpLine(msisdn: "+25779000001", productID: "AIRTIME_1000"),
                    TopUpLine(msisdn: "+25779000002", productID: "AIRTIME_1000")],
            conversationID: "conv_1")

        let result = await services.topUp.quote(request, idempotency: FinanceFixtures.idempotency())

        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/top-up/prepare") })
    }

    // MARK: - Lot

    private static func bulkRoutes(lines: Int = 2) -> [String: String] {
        var routes = FinanceQuotedOperationsTests.routes()
        let bodies = (1...lines).map { index in
            """
            { "financialIntentRef": "fco_b\(index)", "conversationId": "conv_1",
              "status": "READY_FOR_CONFIRMATION", "processRequired": false,
              "amountMinor": 500, "currency": "BIF", "quoteId": "q_b\(index)", "feeMinor": 50,
              "totalMinor": 550, "quoteExpiresAt": "2099-09-09T12:02:00Z",
              "objectVersion": "v1-b\(index)",
              "confirmation": { "confirmationId": "cf_b\(index)", "expiresAt": "2099-09-09T12:02:00Z" } }
            """
        }
        routes["POST /chat-core/financial/top-up/bulk"] = FinanceCoreJSON.wrap(
            #"{ "bulkId": "bulk_1", "lines": [\#(bodies.joined(separator: ","))] }"#)
        return routes
    }

    private static func batchRequest(_ msisdns: [String]) -> TopUpOrderRequest {
        TopUpOrderRequest(lines: msisdns.map { TopUpLine(msisdn: $0, productID: "STUB_AIRTIME_500") },
                          conversationID: "conv_1")
    }

    /// Le lot part sur `/bulk` avec **un seul produit** et la liste des numéros,
    /// et rend un devis confirmable par destinataire.
    func test_batch_quotesEveryLine_onItsOwnFco() async throws {
        let (services, server) = FinanceQuotedOperationsTests.make(Self.bulkRoutes())
        let request = Self.batchRequest(["+25779000001", "+25779000002"])

        let lines = try await services.topUp
            .quoteBatch(request, idempotency: FinanceFixtures.idempotency(key: "bulk-1")).get()

        XCTAssertEqual(lines.map(\.msisdn), ["+25779000001", "+25779000002"])
        XCTAssertEqual(lines.map(\.quote.reference.id), ["fco_b1", "fco_b2"],
                       "Un FCO par ligne — jamais un seul pour le lot")
        XCTAssertEqual(Set(lines.map(\.quote.reference.type)), [.airtime])

        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/top-up/bulk" })
        XCTAssertEqual(call.body["productCode"] as? String, "STUB_AIRTIME_500")
        XCTAssertEqual(call.body["msisdns"] as? [String], ["+25779000001", "+25779000002"])
        XCTAssertEqual(call.body["conversationId"] as? String, "conv_1")
        XCTAssertNotNil(call.body["deviceId"])
        XCTAssertEqual(call.headers["Idempotency-Key"], "bulk-1")
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/top-up/prepare") },
                       "Un lot ne passe pas par le prepare d'une ligne")
    }

    /// Chaque ligne porte **sa** clé de confirmation. Une clé partagée ferait
    /// rendre par le serveur l'issue de la première ligne pour toutes.
    func test_batch_linesDoNotShareASubmissionKey() async throws {
        let (services, _) = FinanceQuotedOperationsTests.make(Self.bulkRoutes())
        let lines = try await services.topUp
            .quoteBatch(Self.batchRequest(["+25779000001", "+25779000002"]),
                        idempotency: FinanceFixtures.idempotency()).get()

        let scopes = lines.map { TransferSubmission.scope(for: $0.quote) }
        XCTAssertEqual(Set(scopes).count, lines.count, "Deux lignes, deux portées de clé")
    }

    /// Le serveur doit rendre autant de lignes qu'on a envoyé de numéros :
    /// c'est l'ordre qui rattache un devis à son destinataire.
    func test_batch_withMismatchedLineCount_isRefused() async {
        var routes = FinanceQuotedOperationsTests.routes()
        routes["POST /chat-core/financial/top-up/bulk"] = FinanceCoreJSON.wrap(
            #"{ "bulkId": "bulk_1", "lines": [] }"#)
        let (services, _) = FinanceQuotedOperationsTests.make(routes)

        let result = await services.topUp.quoteBatch(
            Self.batchRequest(["+25779000001", "+25779000002"]),
            idempotency: FinanceFixtures.idempotency())

        guard case .failure = result else {
            return XCTFail("Un lot dont les lignes ne s'attribuent pas n'est pas confirmable")
        }
    }

    /// Un lot d'un seul numéro n'existe pas : `/prepare` est sa route.
    func test_singleRecipient_doesNotUseTheBulkRoute() async throws {
        var routes = FinanceQuotedOperationsTests.routes()
        routes["POST /chat-core/financial/top-up/prepare"] = FinanceCoreJSON.wrap(#"""
        { "financialIntentRef": "fco_one", "conversationId": "conv_1", "status": "READY_FOR_CONFIRMATION",
          "processRequired": false, "amountMinor": 500, "currency": "BIF", "quoteId": "q_one",
          "quoteExpiresAt": "2099-09-09T12:02:00Z", "objectVersion": "v1",
          "confirmation": { "confirmationId": "cf_one", "expiresAt": "2099-09-09T12:02:00Z" } }
        """#)
        let (services, server) = FinanceQuotedOperationsTests.make(routes)

        _ = try await services.topUp
            .quote(Self.batchRequest(["+25779000001"]), idempotency: FinanceFixtures.idempotency()).get()

        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/top-up/bulk") })
    }

    /// Le prepare porte le produit, le numéro, l'appareil et le canal — son
    /// absence faisait refuser l'execute en `CF_021`.
    func test_quote_sendsTheContractBody() async throws {
        var routes = FinanceQuotedOperationsTests.routes()
        routes["POST /chat-core/financial/top-up/prepare"] = FinanceCoreJSON.wrap(#"""
        { "financialIntentRef": "fco_top", "conversationId": "conv_1", "status": "READY_FOR_CONFIRMATION",
          "processRequired": false, "amountMinor": 1000, "currency": "BIF", "quoteId": "q_t1",
          "feeMinor": 50, "totalMinor": 1050, "quoteExpiresAt": "2099-09-09T12:02:00Z",
          "objectVersion": "v1-tt",
          "confirmation": { "confirmationId": "cf_t1", "expiresAt": "2099-09-09T12:02:00Z" } }
        """#)
        let (services, server) = FinanceQuotedOperationsTests.make(routes)

        let request = TopUpOrderRequest(lines: [TopUpLine(msisdn: "+25779000000",
                                                          productID: "AIRTIME_1000")],
                                        conversationID: "conv_1")
        let quote = try await services.topUp
            .quote(request, idempotency: FinanceFixtures.idempotency(key: "top-1")).get()

        XCTAssertEqual(quote.reference.id, "fco_top")
        XCTAssertEqual(quote.reference.type, .airtime)
        XCTAssertEqual(quote.totalAmount, 1050, "Le total est celui du serveur — jamais recalculé")

        let calls = await server.calls
        let call = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/top-up/prepare" })
        XCTAssertEqual(call.body["productCode"] as? String, "AIRTIME_1000")
        XCTAssertEqual(call.body["msisdn"] as? String, "+25779000000")
        XCTAssertEqual(call.body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(call.body["channel"] as? String, "MOBILE")
        XCTAssertNotNil(call.body["deviceId"])
        XCTAssertEqual(call.headers["Idempotency-Key"], "top-1")
    }

    /// Gel conformité : le devis ne s'ouvre pas, et l'écran n'affiche pas de
    /// clavier de confirmation (§3.2).
    func test_complianceHold_neverOpensTheConfirmation() async {
        var routes = FinanceQuotedOperationsTests.routes()
        routes["POST /chat-core/financial/top-up/prepare"] = FinanceCoreJSON.wrap(
            #"{ "financialIntentRef": "fco_h", "status": "COMPLIANCE_HOLD", "processRequired": true }"#)
        let (services, _) = FinanceQuotedOperationsTests.make(routes)

        let request = TopUpOrderRequest(lines: [TopUpLine(msisdn: "+25779000000",
                                                          productID: "AIRTIME_1000")],
                                        conversationID: "conv_1")
        let result = await services.topUp.quote(request, idempotency: FinanceFixtures.idempotency())
        guard case .failure(.complianceBlocked) = result else { return XCTFail("\(result)") }
    }
}
