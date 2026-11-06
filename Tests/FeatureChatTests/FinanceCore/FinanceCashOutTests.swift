//
//  FinanceCashOutTests.swift
//  FeatureChatTests
//
//  §6 — retrait : jeton émis par Finance, et ce que « consommé » ne veut pas dire.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceCashOutTests: XCTestCase {

    // MARK: - Les routes du contrat

    func test_routes_matchTheContract() {
        let agent = CashAgentRequest(financialIntentRef: "fco_1", conversationId: "c1", agentId: "a1")
        let ref = CashRefRequest(financialIntentRef: "fco_1", conversationId: "c1")
        let token = CashTokenRequest(financialIntentRef: "fco_1", conversationId: "c1",
                                     token: "wtok_1", agentId: "a1")

        XCTAssertEqual(ChatFinanceEndpoints.issueCashOutToken(agent).path,
                       "/chat-core/financial/cash-out/token")
        XCTAssertEqual(ChatFinanceEndpoints.consumeCashOutToken(token).path,
                       "/chat-core/financial/cash-out/token/consume")
        XCTAssertEqual(ChatFinanceEndpoints.revokeCashOutToken(ref).path,
                       "/chat-core/financial/cash-out/token/revoke")
        XCTAssertEqual(ChatFinanceEndpoints.confirmRemittance(ref).path,
                       "/chat-core/financial/cash-out/confirm-remittance")
        XCTAssertEqual(ChatFinanceEndpoints.cashOutIncident(ref).path,
                       "/chat-core/financial/cash-out/incident")
    }

    // MARK: - « Chat n'invente plus de jeton local »

    /// Le jeton vient de Finance. `issue` — qui en rendait un localement —
    /// reste fermé : un code fabriqué ici n'autorise aucun retrait.
    func test_noLocalToken_isEverIssued() async {
        let cashOut = Self.service()

        let issued = await cashOut.issue(
            CashOutRequest(channel: .agent, amount: 1_000, currency: "BIF"),
            idempotency: IdempotencyContext.new(deviceID: "d1"), stepUp: nil)

        guard case .failure(let error) = issued else { return XCTFail("jeton inventé localement") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }

    /// Le code **ne se persiste pas** : le type n'est pas encodable, ce qui
    /// rend l'écriture sur disque impossible à écrire par distraction.
    func test_tokenIsNotPersistable() {
        XCTAssertFalse((CashOutToken.self as Any) is any Codable.Type,
                       "Un code de retrait encodable finirait sur disque")
    }

    // MARK: - Consommer ≠ finalité financière

    /// **L'invariant du §6.** Le code est présenté, `consumedAt` est posé — et
    /// l'argent n'est pas sorti pour autant : `remittedAt` reste vide.
    func test_consumed_isNotSettled() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","conversationId":"c1","channel":"AGENT","agentId":"a1",
         "tokenHash":"h","tokenExpiresAt":"2026-09-25T13:00:00Z","revoked":false,
         "consumedAt":"2026-09-25T12:10:00Z","remittedAt":null,"incidentOpened":false}
        """)

        XCTAssertNotNil(overlay.consumedAt)
        XCTAssertNil(overlay.remittedAt)
        XCTAssertTrue(overlay.awaitsSettlement, "Consommé n'est pas remis")
        XCTAssertFalse(overlay.isUsable(), "Un code consommé n'est plus présentable")
    }

    /// Remis **n'écrit pas le ledger** non plus : c'est un constat de terrain.
    /// L'écran ne peut donc pas en déduire un retrait abouti.
    func test_remitted_stillIsNotALedgerWrite() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","consumedAt":"2026-09-25T12:10:00Z",
         "remittedAt":"2026-09-25T12:12:00Z","revoked":false,"incidentOpened":false}
        """)

        XCTAssertFalse(overlay.awaitsSettlement)
        XCTAssertNotNil(overlay.remittedAt)
    }

    // MARK: - Le code présentable

    func test_revokedToken_isNotUsable() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","revoked":true,"tokenHash":null}
        """)

        XCTAssertFalse(overlay.isUsable())
    }

    func test_expiredToken_isNotUsable() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","revoked":false,
         "tokenExpiresAt":"2020-01-01T00:00:00Z"}
        """)

        XCTAssertFalse(overlay.isUsable())
    }

    func test_freshToken_isUsable() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","revoked":false,
         "tokenExpiresAt":"2099-01-01T00:00:00Z"}
        """)

        XCTAssertTrue(overlay.isUsable())
    }

    /// Un incident ouvert se lit, et n'écrit pas le ledger non plus.
    func test_incidentIsRead() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","incidentOpened":true}
        """)

        XCTAssertTrue(overlay.incidentOpened)
    }

    // MARK: - Aides

    private static let reference = FinancialReference(
        type: .cashOut, id: "fco_1", version: 1, correlationID: CorrelationId())

    private static func overlay(_ json: String) throws -> CashOutTokenOverlay {
        let dto = try JSONDecoder().decode(CashOutOverlayDTO.self, from: Data(json.utf8))
        return CashChannelMapper.overlay(dto, reference: reference)
    }

    private static func service() -> LiveCashOut {
        LiveCashOut(dataSource: CashOutStubSource(),
                    quoting: LiveQuotedOperations(
                        dataSource: CashOutStubSource(), prepared: PreparedIntentStore(),
                        session: FinanceCoreSessionRepository(dataSource: CashOutStubSource(),
                                                              deviceID: { "d1" })),
                    deviceID: { "d1" })
    }
}

private struct CashOutStubSource: RemoteChatFinanceDataSourceProtocol {
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
