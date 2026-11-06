//
//  RemoteChatFinanceDataSourceProtocol.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Raw access to WAANGU Chat Core Finance (`/chat-core`). Returns DTOs and
/// throws `FinanceCoreError`.
///
/// Internal, unlike the other remote protocols: its DTOs are internal to the
/// feature, and only the repositories built on it are exposed.
protocol RemoteChatFinanceDataSourceProtocol: Sendable {

    // MARK: §1.1 Session bootstrap
    func experienceConfig() async throws -> ExperienceConfigDTO
    func governanceCapabilities() async throws -> GovernanceSnapshotDTO
    func securityCapabilities() async throws -> SecurityCapabilitiesDTO
    func sessionResumeState() async throws -> ResumeStateDTO
    func resumeSession(_ request: ResumeSessionRequest) async throws -> ResumeStateDTO
    func hubActions(conversationType: String) async throws -> [ResolvedActionDTO]
    /// §1.1, optional — device preferences. The response shape is not
    /// published, so nothing is read from it.
    func negotiateClientCapabilities(_ request: NegotiateClientCapabilitiesRequest) async throws

    // MARK: §2.2 / §2.3 Hub
    /// Free text read as a **draft** — never a command.
    func parseIntent(_ request: ParseIntentRequest) async throws -> IntentDraftDTO
    /// A one-shot token for a flow opened from a conversation.
    func issueHandoff(_ request: IssueHandoffRequest) async throws -> HandoffTicketDTO
    /// Returns the token's context once, then the token is gone (`CF_025`).
    func consumeHandoff(_ request: ConsumeHandoffRequest) async throws -> HandoffPayloadDTO

    // MARK: §5.1.1 Personal folder
    /// The one-member conversation Core keeps for one's own bills, top-ups and
    /// cash operations — the `conversationId` those flows carry when they are
    /// opened outside a chat.
    func selfConversation() async throws -> SelfConversationDTO

    // MARK: §5.1 Pay bill
    /// A flat list of billers, each carrying its category.
    func billCatalogue(country: String?) async throws -> [BillerCatalogueEntryDTO]
    func billSchema(billerID: String) async throws -> BillerSchemaDTO
    func billInquiry(_ request: BillInquiryRequest) async throws -> BillInquiryDTO

    // MARK: §5.3 Top-up
    /// Products open on this market, for the country of the JWT.
    func topUpCatalogue(country: String?) async throws -> [TopUpProductDTO]
    /// The server normalises the number and names the operator. A client-side
    /// prefix guess is wrong the moment a number is ported — `CF_044`.
    func resolveMsisdn(_ request: TopUpMsisdnRequest) async throws -> ResolvedMsisdnDTO
    /// Payment **and** delivery, as separate statuses. Neither one alone is a success.
    func topUpRequery(_ request: TopUpRefRequest) async throws -> TopUpOverlayDTO
    /// `POST /pay-bill/requery` (§5.1.0) — payment **and** biller fulfilment,
    /// as separate statuses. Paid is not delivered.
    func billRequery(_ request: TopUpRefRequest) async throws -> BillOverlayDTO
    /// `POST /pay-bill/split` (§5.1.2) — arithmetic only: do the parts make the total?
    func billSplitCheck(_ request: PayBillSplitRequest) async throws -> PayBillSplitResultDTO
    /// Several numbers at once. Answers with one `QuotedPrepareResponse` per
    /// line — each its own FCO, each confirmed on its own.
    func topUpBulk(_ request: TopUpBulkRequest,
                   idempotency: IdempotencyContext) async throws -> TopUpBulkResultDTO

    // MARK: §4 Split bill
    /// `POST /split-bill`. Answers with a `RequestView` carrying
    /// `kind: "SPLIT_BILL"` — a split is a money request with named shares.
    func createSplitBill(_ request: CreateSplitBillRequest,
                         idempotency: IdempotencyContext) async throws -> RequestViewDTO
    /// `GET /split-bill/{splitRef}` — the same `RequestView`.
    func splitBill(ref: String) async throws -> RequestViewDTO
    /// `POST /split-bill/pay` — a quote, never a debit.
    func paySplitShare(_ request: PaySplitShareRequest,
                       idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO

    // MARK: §6 Cash-in / Cash-out
    /// Open channels on this market, as **plain codes** — `["AGENT","BANK_BRANCH"]`.
    ///
    /// An **empty list** means none here (`DISABLED` country) — not a failure,
    /// and never a client-side country test.
    func cashInChannels() async throws -> [String]
    func cashOutChannels() async throws -> [String]
    /// Verifying an agent is not depositing — `CF_037` if unknown.
    func verifyAgent(_ request: CashAgentRequest) async throws -> CashInOverlayDTO
    /// The agent received the cash. **Not a credit** — see `CF_038`.
    func confirmPhysical(_ request: CashRefRequest) async throws -> CashInOverlayDTO
    /// The withdrawal code, **issued by Finance** — `CF_051` when not wired.
    func issueCashOutToken(_ request: CashAgentRequest) async throws -> CashOutTokenDTO
    /// The code was presented. **Not a financial finality.**
    func consumeCashOutToken(_ request: CashTokenRequest) async throws -> CashOutOverlayDTO
    func revokeCashOutToken(_ request: CashRefRequest) async throws -> CashOutOverlayDTO
    /// Cash handed over. **Writes no ledger.**
    func confirmRemittance(_ request: CashRefRequest) async throws -> CashOutOverlayDTO
    /// A gap was found. **Writes no ledger.**
    func cashOutIncident(_ request: CashRefRequest) async throws -> CashOutOverlayDTO

    // MARK: §5.2 QR
    /// Reading only, never a payment. The reply's shape is not published yet.
    func parseQR(_ request: ParseQRRequest) async throws -> JSONValue

    // MARK: §3 Send Money and quoted operations
    func resolveBeneficiary(_ request: ResolveBeneficiaryRequest) async throws -> ResolvedBeneficiaryDTO
    func prepareSendMoney(_ request: PrepareSendMoneyRequest,
                          idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO
    func prepareQuoted(_ operation: QuotedOperation, body: [String: Any],
                       idempotency: IdempotencyContext) async throws -> QuotedPrepareResponseDTO
    /// Never retried, whatever the outcome.
    func execute(_ operation: QuotedOperation, _ request: ExecuteIntentRequest,
                 correlationID: CorrelationId) async throws -> ConfirmFinancialIntentResponseDTO

    // MARK: §2 / §9 Financial objects
    func financialObject(ref: String) async throws -> FcoClientCardDTO
    func requery(_ request: RequeryIntentRequest,
                 correlationID: CorrelationId) async throws -> ConfirmFinancialIntentResponseDTO

    // MARK: §4 Request Money
    func createMoneyRequest(_ request: CreateMoneyRequestRequest,
                            idempotency: IdempotencyContext) async throws -> RequestViewDTO
    func moneyRequest(ref: String) async throws -> RequestViewDTO
    func remindMoneyRequest(_ request: RemindMoneyRequestRequest, correlationID: CorrelationId) async throws
    /// A quote to confirm through Send Money's execute — never a debit.
    func payMoneyRequest(_ request: PayMoneyRequestRequest,
                         idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO
    func declineMoneyRequest(_ request: DeclineMoneyRequestRequest, correlationID: CorrelationId) async throws
    /// Phase 10. `CF_046` (202) means requested, not final.
    func cancelIntent(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws
    /// A link to a request — never executable.
    func issuePaymentLink(_ request: IssuePaymentLinkRequest,
                          idempotency: IdempotencyContext) async throws -> PaymentLinkDTO
    /// Context only. The reply's shape is not published: read raw, `requestRef` taken from it.
    func inspectPaymentLink(_ request: InspectPaymentLinkRequest) async throws -> JSONValue

    /// `POST /send-money/quote/refresh` — a new quote, fingerprint and permit for the same FCO; the old fingerprint is void.
    func refreshSendMoneyQuote(_ request: RefreshQuoteRequest) async throws -> PrepareSendMoneyResponseDTO

    /// `POST /receipts/issue` — records the receipt (hash, version). No URL yet.
    func issueReceipt(_ request: IssueReceiptRequest) async throws -> ReceiptRecordDTO
    /// `POST /receipts/share` — the Finance-signed URL (`CF_051` if Finance is not wired).
    func shareReceipt(_ request: TopUpRefRequest) async throws -> ReceiptRecordDTO
    /// `GET /disputes/taxonomy` — the only categories a dispute may carry (`CF_048`).
    func disputeTaxonomy() async throws -> [String]
    /// `POST /disputes` — opens the case in an isolated support thread.
    func openDispute(_ request: OpenDisputeRequest) async throws -> DisputeCaseDTO
    /// `POST /disputes/{id}/evidence` — JSON, not multipart.
    func addDisputeEvidence(disputeID: String, _ request: DisputeEvidenceRequest) async throws -> DisputeCaseDTO
    /// `GET /disputes/{id}` — the case as it stands, for the person who opened it.
    func dispute(id: String) async throws -> DisputeCaseDTO
    /// `GET /disputes/{id}/timeline`.
    func disputeTimeline(id: String) async throws -> [DisputeTimelineStepDTO]
    /// `POST /reversal/request` — Finance executes; Chat only logs.
    func requestReversal(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws -> ReversalRequestedDTO
    /// `POST /receipts/verify`.
    func verifyReceipt(_ request: VerifyReceiptRequest) async throws -> ReceiptRecordDTO
    /// `POST /receipt/share` — the receipt card, published in the conversation.
    func postReceiptCard(_ request: ReceiptCardShareRequest) async throws

    /// `POST /intent/cancel-request` — cancelled before submission; `CF_046` (requested only) after.
    func cancelRequest(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws

    /// `POST /hub/translation/mask` — the values the translation must not touch (`CF_063` if not wired).
    func maskText(_ request: MaskTextRequest) async throws -> MaskedTextDTO
    /// `POST /hub/translation/translate` — the translation, server tokens still in place (`CF_064` if they changed).
    func translateText(_ request: TranslateTextRequest) async throws -> String

    /// `POST /invoice/inquire` — the outstanding amount, from the Merchant Backend (`CF_056` if not wired).
    func inquireInvoice(_ request: InvoiceInquireRequest) async throws -> InvoiceOutstandingDTO

    /// `GET /hub/copilot-tools` — the tools Waangu Copilot may invoke for this user.
    func copilotTools() async throws -> [CopilotToolDTO]
    /// `POST /hub/copilot-tools/invoke` — a message and a hand-off, never an execution (`CF_060`).
    func invokeCopilotTool(_ request: InvokeCopilotToolRequest) async throws -> CopilotToolResultDTO
}

extension RemoteChatFinanceDataSourceProtocol {
    /// Les sources qui ne lisent pas les litiges n'ont rien à rendre.
    func dispute(id: String) async throws -> DisputeCaseDTO { throw FinanceCoreError.missingData }
    func disputeTimeline(id: String) async throws -> [DisputeTimelineStepDTO] { throw FinanceCoreError.missingData }
    func requestReversal(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws -> ReversalRequestedDTO {
        throw FinanceCoreError.missingData
    }
    func verifyReceipt(_ request: VerifyReceiptRequest) async throws -> ReceiptRecordDTO { throw FinanceCoreError.missingData }
    func postReceiptCard(_ request: ReceiptCardShareRequest) async throws { throw FinanceCoreError.missingData }
}
