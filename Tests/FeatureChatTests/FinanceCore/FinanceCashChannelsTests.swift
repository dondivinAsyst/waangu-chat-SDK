//
//  FinanceCashChannelsTests.swift
//  FeatureChatTests
//
//  §6 — canaux d'espèces. Étape 1 : ce que le marché ouvre.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceCashChannelsTests: XCTestCase {

    // MARK: - Les routes

    func test_routes_matchTheContract() {
        XCTAssertEqual(ChatFinanceEndpoints.cashInChannels.path,
                       "/chat-core/financial/cash-in/channels")
        XCTAssertEqual(ChatFinanceEndpoints.cashOutChannels.path,
                       "/chat-core/financial/cash-out/channels")
        XCTAssertEqual(ChatFinanceEndpoints.cashInChannels.method, .get)
        XCTAssertEqual(ChatFinanceEndpoints.cashOutChannels.method, .get)
    }

    // MARK: - Une liste vide reste vide

    /// **Le cas du Canada.** Aucun canal ouvert : le serveur rend `[]`, l'écran
    /// n'affiche rien. Le contrat l'interdit explicitement — « ne pas coder un
    /// `if CA` » — et rien ici ne nomme un pays.
    func test_emptyList_staysEmpty() {
        XCTAssertTrue(CashChannelMapper.cashIn([]).isEmpty)
        XCTAssertTrue(CashChannelMapper.cashOut([]).isEmpty)
    }

    /// Aucun pays n'est écrit dans le mapper : c'est le serveur qui décide.
    func test_mapperNamesNoCountry() throws {
        // Retrouvé par son nom, pas par un chemin écrit en dur : ranger les
        // fichiers par parcours a déplacé celui-ci, et le test cherchait
        // encore l'ancien emplacement.
        let packages = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FinanceCore
            .deletingLastPathComponent()   // FeatureChatTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Packages
        let sources = packages.appendingPathComponent("Sources/FeatureChat")
        let found = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == "LiveCashServices.swift" }
        let file = try XCTUnwrap(found, "LiveCashServices.swift introuvable")
        let source = try String(contentsOf: file, encoding: .utf8)

        for country in ["\"CA\"", "\"BI\"", "\"RW\"", "countryCode ==", "country =="] {
            XCTAssertFalse(source.contains(country),
                           "Le client ne décide pas des canaux par pays : \(country)")
        }
    }

    // MARK: - Lecture des canaux

    /// La forme publiée : une **liste de codes**, `["AGENT","BANK_BRANCH"]`.
    func test_publishedShape_isAListOfCodes() throws {
        let codes = try JSONDecoder().decode(
            [String].self, from: Data("[\"AGENT\",\"BANK_BRANCH\"]".utf8))

        XCTAssertEqual(CashChannelMapper.cashIn(codes), [.agent, .bank])
    }

    func test_cashInCodes_areRead() {
        let channels = CashChannelMapper.cashIn(
            ["AGENT", "BANK_BRANCH", "CARD", "MOBILE_MONEY", "OPEN_BANKING"])

        XCTAssertEqual(channels, [.agent, .bank, .card, .mobileMoney, .openBanking])
    }

    func test_cashOutCodes_areRead() {
        let channels = CashChannelMapper.cashOut(["AGENT", "ATM", "BANK_BRANCH", "MERCHANT"])

        XCTAssertEqual(channels, [.agent, .atm, .bank, .merchant])
    }

    /// `MOBILE_MONEY`, `mobile-money`, `mobileMoney` : un seul canal.
    func test_codeSpelling_doesNotMatter() {
        for spelling in ["MOBILE_MONEY", "mobile-money", "mobileMoney"] {
            XCTAssertEqual(CashChannelMapper.cashIn([spelling]), [.mobileMoney], spelling)
        }
    }

    /// Un canal que cette version ne sait pas instruire est **écarté**, pas
    /// deviné : on n'envoie personne déposer sans pouvoir lui dire où.
    func test_unknownChannel_isDropped_notGuessed() {
        XCTAssertEqual(CashChannelMapper.cashIn(["CRYPTO_ATM", "AGENT"]), [.agent])
    }

    /// Aller-retour : le code renvoyé au prepare est celui que le serveur a
    /// rendu dans `channels`.
    func test_wireRoundTrip() {
        for channel in CashInChannel.allCases {
            XCTAssertEqual(CashChannelMapper.cashIn([CashChannelMapper.wire(channel)]),
                           [channel], channel.rawValue)
        }
        for channel in CashOutChannel.allCases {
            XCTAssertEqual(CashChannelMapper.cashOut([CashChannelMapper.wire(channel)]),
                           [channel], channel.rawValue)
        }
    }

    // MARK: - Étape 2 : le devis de dépôt

    /// Le dépôt passe par un **devis**, jamais par une instruction rendue d'un
    /// seul appel : c'est le `prepare → confirm → execute` du §6.
    func test_liveCashIn_quotesBeforeDepositing() async {
        let cashIn = LiveCashIn(dataSource: CashStubSource(),
                                quoting: Self.quoting(), deviceID: { "d1" })

        XCTAssertTrue(cashIn.providesQuotes)

        // `createInstruction` reste fermé : rendre une instruction ici
        // laisserait croire le dépôt lancé alors que rien ne l'est.
        let direct = await cashIn.createInstruction(
            CashInRequest(channel: .agent, amount: 1_000, currency: "BIF"),
            idempotency: IdempotencyContext.new(deviceID: "d1"))

        guard case .failure(let error) = direct else { return XCTFail("dépôt direct inattendu") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }


    private static func quoting() -> LiveQuotedOperations {
        LiveQuotedOperations(
            dataSource: CashStubSource(), prepared: PreparedIntentStore(),
            session: FinanceCoreSessionRepository(dataSource: CashStubSource(),
                                                  deviceID: { "d1" }))
    }

}

/// Ne répond à rien : les cas qui l'utilisent s'arrêtent avant le réseau.
private struct CashStubSource: RemoteChatFinanceDataSourceProtocol {
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
    func cashInChannels() async throws -> [String] { throw FinanceCoreError.missingData }
    func cashOutChannels() async throws -> [String] { throw FinanceCoreError.missingData }
    func verifyAgent(_ request: CashAgentRequest) async throws -> CashInOverlayDTO { throw FinanceCoreError.missingData }
    func confirmPhysical(_ request: CashRefRequest) async throws -> CashInOverlayDTO { throw FinanceCoreError.missingData }
    func issueCashOutToken(_ request: CashAgentRequest) async throws -> CashOutTokenDTO { throw FinanceCoreError.missingData }
    func consumeCashOutToken(_ request: CashTokenRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func revokeCashOutToken(_ request: CashRefRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func confirmRemittance(_ request: CashRefRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func cashOutIncident(_ request: CashRefRequest) async throws -> CashOutOverlayDTO { throw FinanceCoreError.missingData }
    func createSplitBill(_ request: CreateSplitBillRequest, idempotency: IdempotencyContext) async throws -> RequestViewDTO { throw FinanceCoreError.missingData }
    func splitBill(ref: String) async throws -> RequestViewDTO { throw FinanceCoreError.missingData }
    func paySplitShare(_ request: PaySplitShareRequest, idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO { throw FinanceCoreError.missingData }
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
