//
//  LiveQuotedOperations.swift
//  FeatureChat
//
//  Phase 5 — socle des opérations quotées (INTEGRATION_CHAT_FINANCE.md §5).
//

import Foundation
import WaanguCoreKit

// `QuotedOperation` et ses routes : `ChatFinanceEndpoints.swift`.

/// Ce qu'un prepare — quelle que soit sa forme — apporte à la confirmation.
struct PreparedQuoteFields: Sendable {
    let financialIntentRef: String
    let conversationID: String?
    let status: String?
    let processRequired: Bool?
    let currency: String?
    let principalMinor: Int64?
    let feeMinor: Int64?
    let totalMinor: Int64?
    let fxRate: Decimal?
    let quoteID: String?
    let quoteExpiresAt: String?
    let confirmation: PreparedConfirmationDTO?
    let objectVersion: String?
    let executionPermitID: String?
    let beneficiaryEligible: Bool?

    init(financialIntentRef: String, conversationID: String?, status: String?, processRequired: Bool?,
         currency: String?, principalMinor: Int64?, feeMinor: Int64?, totalMinor: Int64?, fxRate: Decimal?,
         quoteID: String?, quoteExpiresAt: String?, confirmation: PreparedConfirmationDTO?,
         objectVersion: String?, executionPermitID: String?, beneficiaryEligible: Bool?) {
        self.financialIntentRef = financialIntentRef
        self.conversationID = conversationID
        self.status = status
        self.processRequired = processRequired
        self.currency = currency
        self.principalMinor = principalMinor
        self.feeMinor = feeMinor
        self.totalMinor = totalMinor
        self.fxRate = fxRate
        self.quoteID = quoteID
        self.quoteExpiresAt = quoteExpiresAt
        self.confirmation = confirmation
        self.objectVersion = objectVersion
        self.executionPermitID = executionPermitID
        self.beneficiaryEligible = beneficiaryEligible
    }

    init(_ response: QuotedPrepareResponseDTO) {
        self.init(financialIntentRef: response.financialIntentRef, conversationID: response.conversationId,
                  status: response.status, processRequired: response.processRequired,
                  currency: response.currency, principalMinor: response.amountMinor,
                  feeMinor: response.feeMinor, totalMinor: response.totalMinor, fxRate: response.fxRate,
                  quoteID: response.quoteId, quoteExpiresAt: response.quoteExpiresAt,
                  confirmation: response.confirmation, objectVersion: response.objectVersion,
                  executionPermitID: response.executionPermitId, beneficiaryEligible: nil)
    }
}

/// Transforme un prepare en devis confirmable, et le garde pour l'execute.
///
/// Une seule lecture pour toutes les opérations quotées : les règles —
/// gel conformité, statut prêt, expiration lue et jamais inventée — ne
/// s'écrivent qu'une fois.
enum FinanceQuoteAcceptance {

    static func accept(_ fields: PreparedQuoteFields, correlationID: CorrelationId,
                       operation: QuotedOperation, store: PreparedIntentStore) async -> Result<TransferQuote, FinanceError> {
        // Gel conformité : ne pas ouvrir la confirmation — §3.2.
        if fields.processRequired == true || fields.status == "COMPLIANCE_HOLD" {
            return .failure(.complianceBlocked(displayReason: nil))
        }
        guard fields.status == "READY_FOR_CONFIRMATION",
              let quoteID = fields.quoteID, let confirmation = fields.confirmation else {
            return .failure(.server(statusCode: nil))
        }

        let currency = fields.currency ?? ""
        let quoteExpiry = FinanceCoreDates.parse(fields.quoteExpiresAt)
        let confirmationExpiry = FinanceCoreDates.parse(confirmation.expiresAt)
        // Sans expiration lisible, le devis n'est pas confirmable : pas de délai inventé.
        guard let expiresAt = [quoteExpiry, confirmationExpiry].compactMap({ $0 }).min() else {
            return .failure(.expired)
        }

        let quote = TransferQuote(
            reference: FinancialReference(type: operation.objectType, id: fields.financialIntentRef,
                                          version: FinanceCoreRevision.parse(fields.objectVersion) ?? 0,
                                          correlationID: correlationID),
            amount: FcoCardMapper.amount(minor: fields.principalMinor ?? 0, currency: currency),
            currency: currency,
            feeAmount: fields.feeMinor.map { FcoCardMapper.amount(minor: $0, currency: currency) },
            feeCurrency: fields.feeMinor == nil ? nil : currency,
            exchangeRate: fields.fxRate,
            totalAmount: fields.totalMinor.map { FcoCardMapper.amount(minor: $0, currency: currency) },
            totalCurrency: fields.totalMinor == nil ? nil : currency,
            recipientVerification: fields.beneficiaryEligible == false ? .unverified : .verified,
            complianceState: .approved,
            issuedAt: Date(),
            expiresAt: expiresAt
        )
        await store.store(PreparedIntent(
            quote: quote, conversationID: fields.conversationID,
            confirmationID: confirmation.confirmationId, quoteID: quoteID,
            objectVersion: fields.objectVersion, executionPermitID: fields.executionPermitID,
            confirmationExpiresAt: confirmationExpiry ?? expiresAt,
            operation: operation
        ))
        return .success(quote)
    }
}

/// Prepare d'une opération quotée (facture, QR, facture marchande, recharge, espèces).
///
/// **Le corps de chaque prepare n'est pas publié par le contrat** : c'est
/// l'appelant qui le fournit, une fois connu. Le devis rendu se confirme ensuite
/// par le même chemin que Send Money — permis du prepare, execute unique, carte.
struct LiveQuotedOperations: Sendable {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let prepared: PreparedIntentStore
    let session: FinanceCoreSessionRepository

    /// Ce qui interdit d'écrire, s'il y a lieu — session absente, session en
    /// lecture seule, droit à haut risque non accordé.
    ///
    /// Rendu séparément pour les opérations qui n'envoient pas un `prepare`
    /// unique : le lot de recharges a sa propre route (`/top-up/bulk`) mais
    /// doit passer la même porte, et la dupliquer la ferait diverger.
    func writeRefusal(for operation: QuotedOperation) async -> FinanceError? {
        let explanations = FinanceErrorExplanations.shared
        guard let status = await session.status() else {
            return explanations.refuse(.sessionUnavailable)
        }
        if let refusal = status.writeRefusal {
            return explanations.refuse(refusal)
        }
        // Retrait : droit de session à haut risque, fermé tant que non accordé (CF_068).
        if operation == .cashOut,
           await !session.securityAllows(FinanceGovernanceMapper.SecurityRight.cashOut) {
            return explanations.refuse(.highRiskUnavailable)
        }
        return nil
    }

    /// Un `prepare` déjà obtenu, transformé en devis confirmable.
    ///
    /// Les lignes d'un lot arrivent par une seule réponse : chacune repasse ici
    /// pour que gel conformité, statut prêt et expiration lue s'appliquent à
    /// elle comme à n'importe quel devis.
    func accept(_ response: QuotedPrepareResponseDTO, operation: QuotedOperation,
                correlationID: CorrelationId) async -> Result<TransferQuote, FinanceError> {
        await FinanceQuoteAcceptance.accept(PreparedQuoteFields(response),
                                            correlationID: correlationID,
                                            operation: operation,
                                            store: prepared)
    }

    func prepare(_ operation: QuotedOperation, body: [String: Any],
                 idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        if let refusal = await writeRefusal(for: operation) {
            return .failure(refusal)
        }
        switch await FinanceCoreError.capture({
            try await dataSource.prepareQuoted(operation, body: body, idempotency: idempotency)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let response):
            return await FinanceQuoteAcceptance.accept(PreparedQuoteFields(response),
                                                       correlationID: idempotency.correlationID,
                                                       operation: operation,
                                                       store: prepared)
        }
    }
}
