//
//  FinanceSplitBillTests.swift
//  FeatureChatTests
//
//  §4 — partage d'addition : les trois routes du contrat, et rien d'autre.
//

import XCTest
import WaanguCoreKit
import WaanguNetworkKit
@testable import WaanguFeatureChat

final class FinanceSplitBillTests: XCTestCase {

    // MARK: - Les routes du contrat

    func test_routes_matchTheContract() {
        let create = ChatFinanceEndpoints.createSplitBill(Self.draftRequest,
                                                          IdempotencyContext.new(deviceID: "d1"))
        XCTAssertEqual(create.path, "/chat-core/financial/split-bill")
        XCTAssertEqual(create.method, .post)

        XCTAssertEqual(ChatFinanceEndpoints.splitBill(ref: "spl_1").path,
                       "/chat-core/financial/split-bill/spl_1")
        XCTAssertEqual(ChatFinanceEndpoints.splitBill(ref: "spl_1").method, .get)

        let pay = ChatFinanceEndpoints.paySplitShare(Self.payRequest,
                                                     IdempotencyContext.new(deviceID: "d1"))
        XCTAssertEqual(pay.path, "/chat-core/financial/split-bill/pay")
        XCTAssertEqual(pay.method, .post)
    }

    /// Créer et payer sont des écritures : clé d'idempotence dans l'en-tête
    /// **et** dans le corps, sous peine de `CF_071`.
    func test_writes_carryTheIdempotencyKey_inHeaderAndBody() {
        let key = IdempotencyContext.new(deviceID: "d1")
        for endpoint in [ChatFinanceEndpoints.createSplitBill(Self.draftRequest, key),
                         ChatFinanceEndpoints.paySplitShare(Self.payRequest, key)] {
            XCTAssertEqual(endpoint.headers?["Idempotency-Key"], key.key)
            XCTAssertEqual(endpoint.parameters?["idempotencyKey"] as? String, key.key)
            XCTAssertTrue(endpoint.isMutation)
        }
    }

    /// Le corps porte ce que le serveur exige **et** ce que le §50 exige :
    /// les parts nommées, plus le nom, la stratégie et la portée du partage.
    func test_createBody_carriesSharesAndTheContractsFields() {
        let body = ChatFinanceEndpoints
            .createSplitBill(Self.draftRequest, IdempotencyContext.new(deviceID: "d1"))
            .parameters ?? [:]

        XCTAssertEqual(body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(body["label"] as? String, "Dîner")
        XCTAssertEqual(body["currency"] as? String, "BIF")
        XCTAssertEqual(body["totalMinor"] as? Int64, 500)
        XCTAssertEqual(body["strategy"] as? String, "EQUAL")
        XCTAssertEqual(body["privacyScope"] as? String, "OWN_SHARE_ONLY")

        // Une **liste** de parts nommées, pas un dictionnaire.
        let shares = body["shares"] as? [[String: Any]]
        XCTAssertEqual(shares?.count, 2)
        XCTAssertEqual(shares?.first?["userId"] as? String, "u1")
        XCTAssertEqual(shares?.first?["amountMinor"] as? Int64, 250)

        // Pas de `deviceId` : créer un partage ne déplace pas d'argent.
        XCTAssertNil(body["deviceId"])
    }

    /// Payer une part n'envoie **jamais** le total : une part, un consentement.
    func test_payShare_neverCarriesTheTotal() {
        let endpoint = ChatFinanceEndpoints.paySplitShare(Self.payRequest,
                                                          IdempotencyContext.new(deviceID: "d1"))
        let body = endpoint.parameters ?? [:]

        XCTAssertEqual(body["splitRef"] as? String, "spl_1")
        XCTAssertEqual(body["amountMinor"] as? Int64, 5_000)
        XCTAssertNil(body["totalMinor"], "Le total d'un partage ne part pas sur un paiement de part")
    }

    // MARK: - Répartition

    /// La forme relevée sur le serveur : une liste `{userId, amountMinor}`.
    func test_equalSplit_matchesTheServersShape() {
        let shares = LiveSplitBillManaging.shares(of: Self.draft(total: 500, ids: ["u1", "u2"]))

        XCTAssertEqual(shares, [SplitShareRequest(userId: "u1", amountMinor: 250),
                                SplitShareRequest(userId: "u2", amountMinor: 250)])
    }

    /// **Somme exacte, toujours** — `CF_041` sinon. 500 sur trois ne tombe pas
    /// juste : les deux unités restantes vont aux premiers, aucune ne se perd.
    func test_inexactDivision_stillSumsToTheTotal() {
        let shares = LiveSplitBillManaging.shares(of: Self.draft(total: 500, ids: ["u1", "u2", "u3"]))

        XCTAssertEqual(shares.map(\.amountMinor), [167, 167, 166])
        XCTAssertEqual(shares.map(\.amountMinor).reduce(0, +), 500)
    }

    /// Les montants fixés par l'organisateur partent tels quels.
    func test_customAmounts_areSentAsGiven() {
        let draft = Self.draft(total: 10_000, ids: ["u1", "u2"],
                               strategy: .custom(["u1": 6_000, "u2": 4_000]))

        XCTAssertEqual(LiveSplitBillManaging.shares(of: draft),
                       [SplitShareRequest(userId: "u1", amountMinor: 6_000),
                        SplitShareRequest(userId: "u2", amountMinor: 4_000)])
    }

    /// Un poids n'est pas un montant : il se convertit, et la somme tombe juste.
    func test_proportionalWeights_becomeAmounts() {
        let draft = Self.draft(total: 900, ids: ["u1", "u2"],
                               strategy: .proportional(["u1": 2, "u2": 1]))
        let shares = LiveSplitBillManaging.shares(of: draft)

        XCTAssertEqual(shares.map(\.amountMinor), [600, 300])
        XCTAssertEqual(shares.map(\.amountMinor).reduce(0, +), 900)
    }

    // MARK: - §5.1.2 Calculette — le serveur dit si les parts font le total

    /// `valid=false` : rien n'est créé. Un partage dont les parts ne font pas
    /// le total finirait en `CF_041` — autant ne pas l'envoyer.
    func test_create_stops_whenTheServerSaysThePartsDoNotAddUp() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/pay-bill/split"] = FinanceCoreJSON.wrap(
            #"{ "totalMinor": 10000, "parts": [6000, 3000], "valid": false }"#)
        let (services, server) = FinanceRequestMoneyTests.make(routes)
        let draft = Self.draft(total: 10_000, ids: ["u1", "u2"],
                               strategy: .custom(["u1": 6_000, "u2": 3_000]))

        let result = await services.splitBills.create(draft, idempotency: IdempotencyContext.new(deviceID: "d1"))

        guard case .failure(.validation) = result else { return XCTFail("\(result)") }
        let calls = await server.calls
        let check = calls.first { $0.route == "POST /chat-core/financial/pay-bill/split" }
        XCTAssertEqual(check?.body["totalMinor"] as? Int64, 10_000)
        XCTAssertEqual(check?.body["parts"] as? [Int64], [6_000, 3_000])
        XCTAssertFalse(calls.contains { $0.route == "POST /chat-core/financial/split-bill" })
    }

    /// La calculette injoignable ne bloque rien : la création reste juge.
    func test_create_proceeds_whenTheCalculatorIsUnreachable() async {
        let (services, server) = FinanceRequestMoneyTests.make(FinanceSendMoneyTests.routes())
        _ = await services.splitBills.create(Self.draft(total: 500, ids: ["u1", "u2"]),
                                             idempotency: IdempotencyContext.new(deviceID: "d1"))
        let calls = await server.calls
        XCTAssertTrue(calls.contains { $0.route == "POST /chat-core/financial/split-bill" })
    }

    // MARK: - Ce qui n'a pas de route reste fermé

    /// Le contrat ne publie ni liste, ni réponse, ni relance, ni clôture. Les
    /// replier sur une route approchante créerait un second partage au lieu
    /// d'accepter le premier.
    func test_methodsWithoutARoute_stayClosed() async {
        let split = LiveSplitBillManaging(dataSource: SplitStubSource(),
                                          sendMoney: Self.unusedSendMoney(),
                                          deviceID: { "d1" })
        let key = IdempotencyContext.new(deviceID: "d1")

        await assertClosed(await split.respond(splitID: "spl_1", response: .accept, idempotency: key))
        await assertClosed(await split.remind(splitID: "spl_1", participantID: "u2", idempotency: key))
        await assertClosed(await split.close(splitID: "spl_1", idempotency: key))
    }

    /// **Jamais un débit direct.** `contribute` promettait un partage réglé en
    /// un appel ; le contrat rend un devis à confirmer, et rien d'autre.
    func test_contribute_isNeverADirectDebit() async {
        let split = LiveSplitBillManaging(dataSource: SplitStubSource(),
                                          sendMoney: Self.unusedSendMoney(),
                                          deviceID: { "d1" })

        let outcome = await split.contribute(
            splitID: "spl_1",
            amount: Money(minorUnits: 5_000, currency: CurrencyCode(code: "BIF", exponent: 0)),
            idempotency: IdempotencyContext.new(deviceID: "d1"),
            stepUp: nil)

        await assertClosed(outcome)
    }

    /// **Ne jamais parler à la place du serveur.** Sans route de liste, le
    /// client le dit par `listsSplits`, pas par un refus de droits : le Hub
    /// venait d'accorder `SPLIT_BILL`, et « indisponible pour votre compte »
    /// affirmait le contraire de la source de vérité.
    func test_missingListRoute_isNotAnEntitlementRefusal() async {
        let split = LiveSplitBillManaging(dataSource: SplitStubSource(),
                                          sendMoney: Self.unusedSendMoney(),
                                          deviceID: { "d1" })

        XCTAssertFalse(split.listsSplits)
        guard case .success(let list) = await split.splits(cursor: nil) else {
            return XCTFail("un refus de droits inventé par le client")
        }
        XCTAssertTrue(list.isEmpty)
    }

    /// Une implémentation qui ne sait pas devis reste fermée — le défaut du
    /// protocole, pour les doublures locales.
    func test_defaultPayShare_isClosed() async {
        let outcome = await ClosedSplitBillManager().payShare(
            splitID: "spl_1", conversationID: nil, amount: nil,
            idempotency: IdempotencyContext.new(deviceID: "d1"))

        guard case .failure(let error) = outcome else { return XCTFail("devis inattendu") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }

    // MARK: - La réponse du serveur (24/09)

    /// La réponse réelle d'un `POST /split-bill` : un `RequestView` portant
    /// `kind: "SPLIT_BILL"`, la même forme que `/request-money`.
    private static let created = """
    {"requestRef":"b81736e0-85a1-4c25-aa30-009b0c2c9474",
     "conversationId":"a4098b37-db4c-3e19-b9e1-dfbf64b49358",
     "requesterUserId":"110691817141112601","status":"OPEN","processRequired":false,
     "amountMode":"FIXED","currency":"BIF","amountMinor":500,
     "expiresAt":"2026-09-25T14:40:48.206702600Z",
     "parties":[
       {"chatUserId":"100000000000000001","financialPartyId":null,"requestedMinor":250,
        "paidMinor":0,"remainingMinor":250,"currency":"BIF","status":"PENDING"},
       {"chatUserId":"645a3503ddb88a00085da11d","financialPartyId":null,"requestedMinor":250,
        "paidMinor":0,"remainingMinor":250,"currency":"BIF","status":"PENDING"}],
     "note":null,"kind":"SPLIT_BILL",
     "nextSafeActions":["PAY_SHARE","WAIT","CANCEL_INTENT"],
     "complianceCorrelationId":null}
    """

    private func createdView() throws -> RequestViewDTO {
        try JSONDecoder().decode(RequestViewDTO.self, from: Data(Self.created.utf8))
    }

    /// Le partage est lu depuis le `RequestView`, part par part.
    func test_createdSplit_isReadFromTheRequestView() throws {
        let split = LiveSplitBillManaging.split(from: try createdView(),
                                                draft: Self.draft(total: 500, ids: []))

        XCTAssertEqual(split.id, "b81736e0-85a1-4c25-aa30-009b0c2c9474")
        XCTAssertEqual(split.organizerID, "110691817141112601")
        XCTAssertEqual(split.conversationID, "a4098b37-db4c-3e19-b9e1-dfbf64b49358")
        XCTAssertEqual(split.total.minorUnits, 500)
        XCTAssertEqual(split.state, .open)
        XCTAssertEqual(split.participants.count, 2)
        XCTAssertEqual(split.participants.first?.userID, "100000000000000001")
        XCTAssertEqual(split.participants.first?.share.minorUnits, 250)
    }

    /// **Rien n'est dû tant que rien n'est accepté.** `PENDING` ne se lit pas
    /// comme un consentement : aucun débit n'est permis sur cette part.
    func test_pendingParty_cannotBeDebited() throws {
        let split = LiveSplitBillManaging.split(from: try createdView(), draft: nil)

        for participant in split.participants {
            XCTAssertEqual(participant.consent, .pending)
            XCTAssertFalse(participant.consent.canBeDebited)
            XCTAssertTrue(participant.hasOutstandingAmount)
        }
    }

    /// Rien n'est encore versé : le collecté vaut zéro, et le reste le total.
    func test_freshSplit_hasCollectedNothing() throws {
        let split = LiveSplitBillManaging.split(from: try createdView(), draft: nil)

        XCTAssertEqual(split.collected.minorUnits, 0)
        XCTAssertEqual(split.remaining?.minorUnits, 500)
    }

    /// Un état que ce client ne connaît pas ne devient **jamais** un accord.
    func test_unknownPartyStatus_isNotConsent() {
        XCTAssertEqual(LiveSplitBillManaging.consent(of: "SOMETHING_NEW"), .unknown)
        XCTAssertFalse(LiveSplitBillManaging.consent(of: "SOMETHING_NEW").canBeDebited)
        XCTAssertEqual(LiveSplitBillManaging.state(of: "SOMETHING_NEW"), .unknown)
    }

    // MARK: - La carte du participant

    /// Le participant reçoit la carte du partage et doit pouvoir **payer sa
    /// part**. Le serveur l'y autorise par `PAY_SHARE` ; ce code manquait, et
    /// la carte s'affichait sans bouton.
    func test_paySharePartyCanPay() throws {
        let overlay = LiveMoneyRequestResponder.overlay(
            try createdView(),
            reference: Self.reference("b81736e0-85a1-4c25-aa30-009b0c2c9474"),
            me: "100000000000000001")

        XCTAssertTrue(overlay.canPay, "PAY_SHARE doit ouvrir le paiement de sa part")
        XCTAssertTrue(overlay.isSplitBill)
        XCTAssertEqual(overlay.myRemaining, 250)
    }

    /// L'organisateur ne paie pas le partage : il l'a créé.
    func test_organizerDoesNotPay() throws {
        let overlay = LiveMoneyRequestResponder.overlay(
            try createdView(),
            reference: Self.reference("b81736e0-85a1-4c25-aa30-009b0c2c9474"),
            me: "110691817141112601")

        XCTAssertTrue(overlay.isRequester)
        XCTAssertFalse(overlay.canPay)
        XCTAssertTrue(overlay.canCancel, "CANCEL_INTENT est offert au créateur")
    }

    /// Une demande ordinaire n'est pas un partage : elle garde sa route.
    func test_moneyRequestIsNotASplit() throws {
        let payload = Self.created.replacingOccurrences(of: "\"kind\":\"SPLIT_BILL\"",
                                                        with: "\"kind\":\"REQUEST_MONEY\"")
        let view = try JSONDecoder().decode(RequestViewDTO.self, from: Data(payload.utf8))
        let overlay = LiveMoneyRequestResponder.overlay(
            view, reference: Self.reference("r1"), me: "100000000000000001")

        XCTAssertFalse(overlay.isSplitBill)
    }

    /// La carte du participant doit **offrir** un geste : sans cela elle
    /// arrivait dans son fil, montrait sa part, et ne menait nulle part.
    func test_participantCard_offersAnAction() throws {
        let overlay = LiveMoneyRequestResponder.overlay(
            try createdView(),
            reference: Self.reference("b81736e0-85a1-4c25-aa30-009b0c2c9474"),
            me: "100000000000000001")

        XCTAssertTrue(RequestActionRow.hasActions(overlay))
    }

    /// Le créateur, lui, garde ses propres gestes — annuler, pas payer.
    func test_creatorCard_offersCancelNotPay() throws {
        let overlay = LiveMoneyRequestResponder.overlay(
            try createdView(),
            reference: Self.reference("b81736e0-85a1-4c25-aa30-009b0c2c9474"),
            me: "110691817141112601")

        XCTAssertTrue(RequestActionRow.hasActions(overlay))
        XCTAssertFalse(overlay.canPay)
    }

    // MARK: - Aides

    private func assertClosed<T>(_ outcome: Result<T, FinanceError>,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        guard case .failure(let error) = outcome else {
            return XCTFail("succès inattendu sans route", file: file, line: line)
        }
        XCTAssertEqual(error, .capabilityUnavailable, file: file, line: line)
    }

    private static let draftRequest = CreateSplitBillRequest(
        conversationId: "conv_1", label: "Dîner", currency: "BIF", totalMinor: 500,
        strategy: "EQUAL", privacyScope: "OWN_SHARE_ONLY",
        shares: [SplitShareRequest(userId: "u1", amountMinor: 250),
                 SplitShareRequest(userId: "u2", amountMinor: 250)])

    private static func reference(_ id: String) -> FinancialReference {
        FinancialReference(type: .payment, id: id, version: 1, correlationID: CorrelationId())
    }

    private static func draft(total: Int64, ids: [String],
                              strategy: SplitStrategy = .equal) -> SplitBillDraft {
        SplitBillDraft(labelKey: "Dîner",
                       total: Money(minorUnits: total, currency: CurrencyCode(code: "BIF", exponent: 0)),
                       participantIDs: ids, strategy: strategy, privacyScope: .ownShareOnly,
                       conversationID: "conv_1")
    }

    private static let payRequest = PaySplitShareRequest(
        splitRef: "spl_1", conversationId: "conv_1", amountMinor: 5_000,
        currency: "BIF", channel: "MOBILE", deviceId: "d1")

    /// Jamais appelé par ces cas : les méthodes éprouvées ici n'atteignent pas
    /// le réseau.
    private static func unusedSendMoney() -> LiveSendMoney {
        LiveSendMoney(dataSource: SplitStubSource(), prepared: PreparedIntentStore(),
                      session: FinanceCoreSessionRepository(dataSource: SplitStubSource(),
                                                            deviceID: { "d1" }),
                      deviceID: { "d1" }, directory: FinanceCoreDirectory())
    }
}

// MARK: - Doublure

/// Ne répond à rien : les cas qui l'utilisent s'arrêtent avant le réseau.
private struct SplitStubSource: RemoteChatFinanceDataSourceProtocol {
    func experienceConfig() async throws -> ExperienceConfigDTO { throw FinanceCoreError.missingData }
    func governanceCapabilities() async throws -> GovernanceSnapshotDTO { throw FinanceCoreError.missingData }
    func securityCapabilities() async throws -> SecurityCapabilitiesDTO { throw FinanceCoreError.missingData }
    func sessionResumeState() async throws -> ResumeStateDTO { throw FinanceCoreError.missingData }
    func resumeSession(_ request: ResumeSessionRequest) async throws -> ResumeStateDTO { throw FinanceCoreError.missingData }
    func hubActions(conversationType: String) async throws -> [ResolvedActionDTO] { throw FinanceCoreError.missingData }
    func copilotTools() async throws -> [CopilotToolDTO] { throw FinanceCoreError.missingData }
    func invokeCopilotTool(_ request: InvokeCopilotToolRequest) async throws -> CopilotToolResultDTO { throw FinanceCoreError.missingData }
    func inquireInvoice(_ request: InvoiceInquireRequest) async throws -> InvoiceOutstandingDTO { throw FinanceCoreError.missingData }
    func maskText(_ request: MaskTextRequest) async throws -> MaskedTextDTO { throw FinanceCoreError.missingData }
    func translateText(_ request: TranslateTextRequest) async throws -> String { throw FinanceCoreError.missingData }
    func cancelRequest(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws { throw FinanceCoreError.missingData }
    func issueReceipt(_ request: IssueReceiptRequest) async throws -> ReceiptRecordDTO { throw FinanceCoreError.missingData }
    func shareReceipt(_ request: TopUpRefRequest) async throws -> ReceiptRecordDTO { throw FinanceCoreError.missingData }
    func disputeTaxonomy() async throws -> [String] { throw FinanceCoreError.missingData }
    func openDispute(_ request: OpenDisputeRequest) async throws -> DisputeCaseDTO { throw FinanceCoreError.missingData }
    func addDisputeEvidence(disputeID: String, _ request: DisputeEvidenceRequest) async throws -> DisputeCaseDTO { throw FinanceCoreError.missingData }
    func refreshSendMoneyQuote(_ request: RefreshQuoteRequest) async throws -> PrepareSendMoneyResponseDTO { throw FinanceCoreError.missingData }
    func negotiateClientCapabilities(_ request: NegotiateClientCapabilitiesRequest) async throws { throw FinanceCoreError.missingData }
    func parseIntent(_ request: ParseIntentRequest) async throws -> IntentDraftDTO { throw FinanceCoreError.missingData }
    func issueHandoff(_ request: IssueHandoffRequest) async throws -> HandoffTicketDTO { throw FinanceCoreError.missingData }
    func consumeHandoff(_ request: ConsumeHandoffRequest) async throws -> HandoffPayloadDTO { throw FinanceCoreError.missingData }
    func selfConversation() async throws -> SelfConversationDTO { throw FinanceCoreError.missingData }
    func billCatalogue(country: String?) async throws -> [BillerCatalogueEntryDTO] { throw FinanceCoreError.missingData }
    func billSchema(billerID: String) async throws -> BillerSchemaDTO { throw FinanceCoreError.missingData }
    func billInquiry(_ request: BillInquiryRequest) async throws -> BillInquiryDTO { throw FinanceCoreError.missingData }
    func topUpCatalogue(country: String?) async throws -> [TopUpProductDTO] { throw FinanceCoreError.missingData }
    func resolveMsisdn(_ request: TopUpMsisdnRequest) async throws -> ResolvedMsisdnDTO { throw FinanceCoreError.missingData }
    func topUpRequery(_ request: TopUpRefRequest) async throws -> TopUpOverlayDTO { throw FinanceCoreError.missingData }
    func billRequery(_ request: TopUpRefRequest) async throws -> BillOverlayDTO { throw FinanceCoreError.missingData }
    func billSplitCheck(_ request: PayBillSplitRequest) async throws -> PayBillSplitResultDTO { throw FinanceCoreError.missingData }
    func topUpBulk(_ request: TopUpBulkRequest, idempotency: IdempotencyContext) async throws -> TopUpBulkResultDTO { throw FinanceCoreError.missingData }
    func createSplitBill(_ request: CreateSplitBillRequest, idempotency: IdempotencyContext) async throws -> RequestViewDTO { throw FinanceCoreError.missingData }
    func splitBill(ref: String) async throws -> RequestViewDTO { throw FinanceCoreError.missingData }
    func paySplitShare(_ request: PaySplitShareRequest, idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO { throw FinanceCoreError.missingData }
    func cashInChannels() async throws -> [String] { throw FinanceCoreError.missingData }
    func cashOutChannels() async throws -> [String] { throw FinanceCoreError.missingData }
    func verifyAgent(_ request: CashAgentRequest) async throws -> CashInOverlayDTO { throw FinanceCoreError.missingData }
    func confirmPhysical(_ request: CashRefRequest) async throws -> CashInOverlayDTO { throw FinanceCoreError.missingData }
    func issueCashOutToken(_ request: CashAgentRequest) async throws -> CashOutTokenDTO { throw FinanceCoreError.missingData }
    func consumeCashOutToken(_ request: CashTokenRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func revokeCashOutToken(_ request: CashRefRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func confirmRemittance(_ request: CashRefRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func cashOutIncident(_ request: CashRefRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func parseQR(_ request: ParseQRRequest) async throws -> JSONValue { throw FinanceCoreError.missingData }
    func resolveBeneficiary(_ request: ResolveBeneficiaryRequest) async throws -> ResolvedBeneficiaryDTO { throw FinanceCoreError.missingData }
    func prepareSendMoney(_ request: PrepareSendMoneyRequest, idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO { throw FinanceCoreError.missingData }
    func prepareQuoted(_ operation: QuotedOperation, body: [String: Any], idempotency: IdempotencyContext) async throws -> QuotedPrepareResponseDTO { throw FinanceCoreError.missingData }
    func execute(_ operation: QuotedOperation, _ request: ExecuteIntentRequest, correlationID: CorrelationId) async throws -> ConfirmFinancialIntentResponseDTO { throw FinanceCoreError.missingData }
    func financialObject(ref: String) async throws -> FcoClientCardDTO { throw FinanceCoreError.missingData }
    func requery(_ request: RequeryIntentRequest, correlationID: CorrelationId) async throws -> ConfirmFinancialIntentResponseDTO { throw FinanceCoreError.missingData }
    func createMoneyRequest(_ request: CreateMoneyRequestRequest, idempotency: IdempotencyContext) async throws -> RequestViewDTO { throw FinanceCoreError.missingData }
    func moneyRequest(ref: String) async throws -> RequestViewDTO { throw FinanceCoreError.missingData }
    func remindMoneyRequest(_ request: RemindMoneyRequestRequest, correlationID: CorrelationId) async throws { throw FinanceCoreError.missingData }
    func payMoneyRequest(_ request: PayMoneyRequestRequest, idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO { throw FinanceCoreError.missingData }
    func declineMoneyRequest(_ request: DeclineMoneyRequestRequest, correlationID: CorrelationId) async throws { throw FinanceCoreError.missingData }
    func cancelIntent(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws { throw FinanceCoreError.missingData }
    func issuePaymentLink(_ request: IssuePaymentLinkRequest, idempotency: IdempotencyContext) async throws -> PaymentLinkDTO { throw FinanceCoreError.missingData }
    func inspectPaymentLink(_ request: InspectPaymentLinkRequest) async throws -> JSONValue { throw FinanceCoreError.missingData }
}
