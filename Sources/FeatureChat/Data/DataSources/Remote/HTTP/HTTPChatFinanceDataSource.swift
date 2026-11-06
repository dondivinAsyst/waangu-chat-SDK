//
//  HTTPChatFinanceDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

/// Échec d'un appel Chat Core Finance.
enum FinanceCoreError: Error, Equatable, Sendable {
    /// Refus métier : l'enveloppe portait `error.code`, et le message que le
    /// serveur a rédigé pour l'utilisateur. **La logique ne lit que le code.**
    case business(FinanceCoreErrorCode, message: String?)
    /// Échec de transport, déjà traduit selon qu'il est survenu avant ou après envoi.
    case transport(FinanceError)
    /// `success=true` sans `data` là où le contrat en exige.
    case missingData

    /// Vue unifiée pour les écrans, qui consomment `FinanceError`.
    var financeError: FinanceError {
        switch self {
        case .business(let code, _): return code.financeError
        case .transport(let error): return error
        case .missingData:          return .server(statusCode: nil)
        }
    }

    /// Exécute un appel de la source et rend son issue comme `Result`.
    ///
    /// Les contrats CoreKit que servent les repositories sont en `Result` ;
    /// ce pont évite d'écrire un `do/catch` à chaque lecture. La source ne lève
    /// que des `FinanceCoreError` — toute autre erreur est un défaut, traité
    /// comme une réponse serveur illisible, jamais comme un succès.
    static func capture<T>(_ operation: () async throws -> T) async -> Result<T, FinanceCoreError> {
        do {
            return .success(try await operation())
        } catch let error as FinanceCoreError {
            return .failure(error)
        } catch {
            return .failure(.transport(.server(statusCode: nil)))
        }
    }
}

/// Chat Core Finance sur le client HTTP du chat (`chatUrl`).
///
/// Le client HTTP garde tout ce qu'il fait déjà : jeton, retry selon
/// l'idempotence déclarée, disjoncteur, épinglage. Cette source ne fait que
/// lire l'enveloppe et nommer l'échec.
final class HTTPChatFinanceDataSource: RemoteChatFinanceDataSourceProtocol, @unchecked Sendable {

    private let httpClient: APIClientProtocol
    private let errorMapper: APIErrorMapper
    private let onSessionInvalid: (@Sendable () async -> Void)?

    /// - Parameter onSessionInvalid: appelé quand le serveur déclare la session
    ///   périmée — `CF_066` (reprise requise), `CF_070` (époque périmée),
    ///   `CF_006`/`CF_012` (capacité périmée). Garder l'instantané en cache
    ///   laisserait l'écran proposer des actions que le serveur refusera.
    init(httpClient: APIClientProtocol,
         errorMapper: APIErrorMapper = APIErrorMapper(),
         onSessionInvalid: (@Sendable () async -> Void)? = nil) {
        self.httpClient = httpClient
        self.errorMapper = errorMapper
        self.onSessionInvalid = onSessionInvalid
    }

    // MARK: - §1.1 Session

    func experienceConfig() async throws -> ExperienceConfigDTO {
        try await send(.experienceConfig)
    }

    func governanceCapabilities() async throws -> GovernanceSnapshotDTO {
        try await send(.governanceCapabilities)
    }

    func securityCapabilities() async throws -> SecurityCapabilitiesDTO {
        try await send(.securityCapabilities)
    }

    func sessionResumeState() async throws -> ResumeStateDTO {
        try await send(.sessionResumeState)
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> ResumeStateDTO {
        try await send(.resumeSession(request))
    }

    func hubActions(conversationType: String) async throws -> [ResolvedActionDTO] {
        try await send(.hubActions(conversationType: conversationType))
    }

    func negotiateClientCapabilities(_ request: NegotiateClientCapabilitiesRequest) async throws {
        let _: JSONValue = try await send(.negotiateClientCapabilities(request))
    }

    func parseIntent(_ request: ParseIntentRequest) async throws -> IntentDraftDTO {
        try await send(.parseIntent(request))
    }

    func issueHandoff(_ request: IssueHandoffRequest) async throws -> HandoffTicketDTO {
        try await send(.issueHandoff(request))
    }

    func consumeHandoff(_ request: ConsumeHandoffRequest) async throws -> HandoffPayloadDTO {
        try await send(.consumeHandoff(request))
    }

    // MARK: - §5.1.1 Dossier personnel

    func selfConversation() async throws -> SelfConversationDTO {
        let folder: SelfConversationDTO = try await send(.selfConversation)
        // L'époque arrive ici et nulle part ailleurs pour ce dossier : la
        // retenir tout de suite évite un premier prepare sans `X-Membership-Epoch`.
        if let epoch = folder.membershipEpoch {
            FinanceMembershipEpochs.shared.remember(epoch, for: folder.conversationId)
        }
        return folder
    }

    // MARK: - §3 Send Money

    func billCatalogue(country: String?) async throws -> [BillerCatalogueEntryDTO] {
        try await send(.billCatalogue(country: country))
    }

    func billSchema(billerID: String) async throws -> BillerSchemaDTO {
        try await send(.billSchema(billerID: billerID))
    }

    func billInquiry(_ request: BillInquiryRequest) async throws -> BillInquiryDTO {
        try await send(.billInquiry(request))
    }

    // MARK: - §5.3 Recharge

    func topUpCatalogue(country: String?) async throws -> [TopUpProductDTO] {
        try await send(.topUpCatalogue(country: country))
    }

    func resolveMsisdn(_ request: TopUpMsisdnRequest) async throws -> ResolvedMsisdnDTO {
        try await send(.resolveMsisdn(request))
    }

    func topUpRequery(_ request: TopUpRefRequest) async throws -> TopUpOverlayDTO {
        try await send(.topUpRequery(request))
    }

    func billRequery(_ request: TopUpRefRequest) async throws -> BillOverlayDTO {
        try await send(.billRequery(request))
    }

    func billSplitCheck(_ request: PayBillSplitRequest) async throws -> PayBillSplitResultDTO {
        try await send(.billSplitCheck(request))
    }

    func topUpBulk(_ request: TopUpBulkRequest,
                   idempotency: IdempotencyContext) async throws -> TopUpBulkResultDTO {
        try await send(.topUpBulk(request, idempotency))
    }

    // MARK: - §6 Espèces

    func cashInChannels() async throws -> [String] {
        try await send(.cashInChannels)
    }

    func cashOutChannels() async throws -> [String] {
        try await send(.cashOutChannels)
    }

    func verifyAgent(_ request: CashAgentRequest) async throws -> CashInOverlayDTO {
        try await send(.verifyAgent(request))
    }

    func confirmPhysical(_ request: CashRefRequest) async throws -> CashInOverlayDTO {
        try await send(.confirmPhysical(request))
    }

    func issueCashOutToken(_ request: CashAgentRequest) async throws -> CashOutTokenDTO {
        try await send(.issueCashOutToken(request))
    }

    func consumeCashOutToken(_ request: CashTokenRequest) async throws -> CashOutOverlayDTO {
        try await send(.consumeCashOutToken(request))
    }

    func revokeCashOutToken(_ request: CashRefRequest) async throws -> CashOutOverlayDTO {
        try await send(.revokeCashOutToken(request))
    }

    func confirmRemittance(_ request: CashRefRequest) async throws -> CashOutOverlayDTO {
        try await send(.confirmRemittance(request))
    }

    func cashOutIncident(_ request: CashRefRequest) async throws -> CashOutOverlayDTO {
        try await send(.cashOutIncident(request))
    }

    func parseQR(_ request: ParseQRRequest) async throws -> JSONValue {
        try await send(.parseQR(request))
    }

    // MARK: - §4 Partage d'addition

    func createSplitBill(_ request: CreateSplitBillRequest,
                         idempotency: IdempotencyContext) async throws -> RequestViewDTO {
        try await send(.createSplitBill(request, idempotency))
    }

    func splitBill(ref: String) async throws -> RequestViewDTO {
        try await send(.splitBill(ref: ref))
    }

    func paySplitShare(_ request: PaySplitShareRequest,
                       idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO {
        try await send(.paySplitShare(request, idempotency))
    }

    func resolveBeneficiary(_ request: ResolveBeneficiaryRequest) async throws -> ResolvedBeneficiaryDTO {
        try await send(.resolveBeneficiary(request))
    }

    func prepareSendMoney(_ request: PrepareSendMoneyRequest,
                          idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO {
        try await send(.prepareSendMoney(request, idempotency))
    }

    func prepareQuoted(_ operation: QuotedOperation, body: [String: Any],
                       idempotency: IdempotencyContext) async throws -> QuotedPrepareResponseDTO {
        try await send(.prepareQuoted(operation, body: body, idempotency))
    }

    func execute(_ operation: QuotedOperation, _ request: ExecuteIntentRequest,
                 correlationID: CorrelationId) async throws -> ConfirmFinancialIntentResponseDTO {
        try await send(.execute(operation, request, correlationID))
    }

    // MARK: - §2 / §9 Objets

    func financialObject(ref: String) async throws -> FcoClientCardDTO {
        try await send(.financialObject(ref: ref))
    }

    func requery(_ request: RequeryIntentRequest,
                 correlationID: CorrelationId) async throws -> ConfirmFinancialIntentResponseDTO {
        try await send(.requery(request, correlationID))
    }

    // MARK: - §4 Request Money

    func createMoneyRequest(_ request: CreateMoneyRequestRequest,
                            idempotency: IdempotencyContext) async throws -> RequestViewDTO {
        try await send(.createMoneyRequest(request, idempotency))
    }

    func moneyRequest(ref: String) async throws -> RequestViewDTO {
        try await send(.moneyRequest(ref: ref))
    }

    func remindMoneyRequest(_ request: RemindMoneyRequestRequest, correlationID: CorrelationId) async throws {
        let _: FinanceCoreEmpty = try await send(.remindMoneyRequest(request, correlationID))
    }

    func payMoneyRequest(_ request: PayMoneyRequestRequest,
                         idempotency: IdempotencyContext) async throws -> PrepareSendMoneyResponseDTO {
        try await send(.payMoneyRequest(request, idempotency))
    }

    func declineMoneyRequest(_ request: DeclineMoneyRequestRequest, correlationID: CorrelationId) async throws {
        let _: FinanceCoreEmpty = try await send(.declineMoneyRequest(request, correlationID))
    }

    func cancelIntent(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws {
        let _: FinanceCoreEmpty = try await send(.cancelIntent(request, correlationID))
    }

    func issuePaymentLink(_ request: IssuePaymentLinkRequest,
                          idempotency: IdempotencyContext) async throws -> PaymentLinkDTO {
        try await send(.issuePaymentLink(request, idempotency))
    }

    func inspectPaymentLink(_ request: InspectPaymentLinkRequest) async throws -> JSONValue {
        try await send(.inspectPaymentLink(request))
    }

    // MARK: - Envoi

    func refreshSendMoneyQuote(_ request: RefreshQuoteRequest) async throws -> PrepareSendMoneyResponseDTO {
        try await send(.refreshSendMoneyQuote(request))
    }

    func issueReceipt(_ request: IssueReceiptRequest) async throws -> ReceiptRecordDTO {
        try await send(.issueReceipt(request))
    }

    func shareReceipt(_ request: TopUpRefRequest) async throws -> ReceiptRecordDTO {
        try await send(.shareReceipt(request))
    }

    func disputeTaxonomy() async throws -> [String] {
        try await send(.disputeTaxonomy)
    }

    func openDispute(_ request: OpenDisputeRequest) async throws -> DisputeCaseDTO {
        try await send(.openDispute(request))
    }

    func addDisputeEvidence(disputeID: String, _ request: DisputeEvidenceRequest) async throws -> DisputeCaseDTO {
        try await send(.addDisputeEvidence(disputeID: disputeID, request))
    }

    func dispute(id: String) async throws -> DisputeCaseDTO {
        try await send(.dispute(id: id))
    }

    func disputeTimeline(id: String) async throws -> [DisputeTimelineStepDTO] {
        try await send(.disputeTimeline(id: id))
    }

    func requestReversal(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws -> ReversalRequestedDTO {
        try await send(.requestReversal(request, correlationID))
    }

    func verifyReceipt(_ request: VerifyReceiptRequest) async throws -> ReceiptRecordDTO {
        try await send(.verifyReceipt(request))
    }

    func postReceiptCard(_ request: ReceiptCardShareRequest) async throws {
        let _: FinanceCoreEmpty = try await send(.postReceiptCard(request))
    }

    /// - Parameter isRetry: `true` pour la seconde tentative après un refresh de
    ///   capacité — il n'y en a jamais de troisième.
    func cancelRequest(_ request: CancelIntentRequest, correlationID: CorrelationId) async throws {
        let _: FinanceCoreEmpty = try await send(.cancelRequest(request, correlationID))
    }

    func maskText(_ request: MaskTextRequest) async throws -> MaskedTextDTO {
        try await send(.maskText(request))
    }

    func translateText(_ request: TranslateTextRequest) async throws -> String {
        try await send(.translateText(request))
    }

    func inquireInvoice(_ request: InvoiceInquireRequest) async throws -> InvoiceOutstandingDTO {
        try await send(.inquireInvoice(request))
    }

    func copilotTools() async throws -> [CopilotToolDTO] {
        try await send(.copilotTools)
    }

    func invokeCopilotTool(_ request: InvokeCopilotToolRequest) async throws -> CopilotToolResultDTO {
        try await send(.invokeCopilotTool(request))
    }

    private func send<Payload: Decodable>(_ endpoint: ChatFinanceEndpoints,
                                          isRetry: Bool = false) async throws -> Payload {
        let response: ChatCoreAPIResponse<Payload>
        do {
            response = try await httpClient.request(endpoint: endpoint)
        } catch {
            throw FinanceCoreError.transport(
                Self.financeError(for: error, endpoint: endpoint, mapper: errorMapper))
        }

        switch Self.unwrap(response) {
        case .success(let payload):
            return payload
        case .failure(let failure):
            if case .business(let code, let message) = failure {
                // Le texte suit l'erreur jusqu'à l'écran ; aucune décision ne le lit.
                FinanceErrorExplanations.shared.record(serverMessage: message, for: code.financeError)
                // `.resyncMembership` (`CF_074`) : l'époque envoyée n'est plus
                // celle du serveur. Ce qu'on en savait est faux, y compris le
                // dossier personnel qui la portait — tout oublier fait relire,
                // et la prochaine écriture repart de l'époque courante au lieu
                // de rejouer celle qui vient d'être refusée.
                if [.resumeSession, .relogin, .refreshCapability, .resyncMembership]
                    .contains(code.clientAction) {
                    await onSessionInvalid?()
                }
                // `CF_006` / `CF_012` : la capacité est périmée, pas refusée.
                // `POST /capability/refresh` (§12), puis **une** seconde
                // tentative — jamais pour un execute ni un jeton à usage
                // unique, que `isIdempotent` exclut : rejouer un execute est
                // l'interdit du §0.3.3.
                if code.clientAction == .refreshCapability, !isRetry, endpoint.isIdempotent {
                    if case .refreshCapability = endpoint { throw failure }
                    do {
                        let _: FinanceCoreEmpty = try await send(.refreshCapability, isRetry: true)
                    } catch {
                        throw failure
                    }
                    return try await send(endpoint, isRetry: true)
                }
            }
            throw failure
        }
    }

    // MARK: - Lecture de l'enveloppe

    static func unwrap<Payload: Decodable>(_ response: ChatCoreAPIResponse<Payload>) -> Result<Payload, FinanceCoreError> {
        // Un code métier l'emporte sur `success`, qui peut manquer de cohérence.
        if let code = response.error?.code, !code.isEmpty {
            // Le message de l'erreur, ou à défaut celui de l'enveloppe.
            return .failure(.business(FinanceCoreErrorCode(rawValue: code),
                                      message: response.error?.message ?? response.message))
        }
        guard response.success else { return .failure(.transport(.server(statusCode: response.statusCode))) }
        if let data = response.data { return .success(data) }
        if let empty = FinanceCoreEmpty() as? Payload { return .success(empty) }
        return .failure(.missingData)
    }

    // MARK: - Avant ou après envoi

    /// Le même échec n'a pas le même sens selon qu'il a pu atteindre le serveur.
    ///
    /// Une lecture qui échoue n'est jamais une ambiguïté financière. Une écriture
    /// l'est dès que la requête a pu partir : un délai dépassé après un execute
    /// peut cacher un débit. Seuls les refus locaux — pas de réseau, disjoncteur
    /// ouvert, débit limité, URL invalide — prouvent que rien n'est parti.
    static func financeError(for error: Error, endpoint: ChatFinanceEndpoints,
                             mapper: APIErrorMapper) -> FinanceError {
        let apiError = error as? APIError
        let neverSent: Bool
        switch apiError {
        case .noInternetConnection?, .circuitBreakerOpen?, .rateLimited?, .invalidURL?:
            neverSent = true
        default:
            neverSent = false
        }
        return FinanceError.from(mapper.map(error),
                                 afterSubmission: endpoint.isMutation && !neverSent)
    }
}
