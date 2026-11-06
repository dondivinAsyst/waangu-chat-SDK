//
//  LiveSendMoney.swift
//  FeatureChat
//
//  Phase 3 — Send Money sur Chat Core (INTEGRATION_CHAT_FINANCE.md §3).
//

import Foundation
import WaanguCoreKit

/// Ce que le prepare a rendu, gardé jusqu'à l'execute.
///
/// Le prepare livre en une fois le devis, l'empreinte de confirmation et le
/// permis. Le contrat ajoute : « le refresh **invalide** l'ancien fingerprint ».
/// Redemander un devis à chaque confirmation tuerait donc la confirmation
/// qu'elle vient d'accepter (CF_021/022). On garde le prepare, on le ressert.
struct PreparedIntent: Equatable, Sendable {
    let quote: TransferQuote
    let conversationID: String?
    let confirmationID: String
    let quoteID: String
    let objectVersion: String?
    let executionPermitID: String?
    let confirmationExpiresAt: Date
    /// Opération qui a préparé — Send Money, facture, QR… — et donc la route
    /// sur laquelle son execute part.
    var operation: QuotedOperation = .sendMoney
}

actor PreparedIntentStore {
    private var intents: [String: PreparedIntent] = [:]

    func store(_ intent: PreparedIntent) { intents[intent.quote.reference.id] = intent }
    func intent(for reference: String) -> PreparedIntent? { intents[reference] }
    /// Empreinte à usage unique : une fois l'execute parti, elle ne se ressert plus.
    func consume(_ reference: String) { intents[reference] = nil }
    /// Changement de compte : rien du précédent ne doit rester confirmable.
    func clear() { intents.removeAll() }
}

/// `RecipientResolving`, `TransferQuoting` et `ExecutionPermitIssuing` servis par Chat Core.
struct LiveSendMoney: RecipientResolving, TransferQuoting, ExecutionPermitIssuing {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let prepared: PreparedIntentStore
    let session: FinanceCoreSessionRepository
    let deviceID: @Sendable () -> String
    var directory: FinanceCoreDirectory? = nil

    // MARK: - §3.1 Bénéficiaire

    func resolve(_ input: RecipientInput) async -> Result<ResolvedRecipient, FinanceError> {
        await resolve(input, knownAs: nil)
    }

    func resolve(_ input: RecipientInput, knownAs localName: String?) async -> Result<ResolvedRecipient, FinanceError> {
        var request = ResolveBeneficiaryRequest()
        switch input {
        case .phoneNumber(let msisdn), .mobileMoney(_, let msisdn): request.msisdn = msisdn
        case .walletHandle(let handle):                             request.walletRef = handle
        // Hors Send Money : QR, marchand, banque, retrait ont leurs propres parcours.
        case .merchantCode, .qrPayload, .bankAccount, .cashPickup:
            return .failure(.recipientUnresolved(reason: .notFound))
        }
        // Indication seulement : le serveur ne résout jamais sur un nom (CF_028).
        if let localName, !localName.isEmpty { request.displayNameHint = localName }

        switch await FinanceCoreError.capture({ try await dataSource.resolveBeneficiary(request) }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let beneficiary):
            guard beneficiary.eligible == true else {
                return .failure(.recipientUnresolved(reason: .ineligible))
            }
            // Request Money exigera l'utilisateur Chat derrière ce jeton.
            await directory?.remember(token: beneficiary.beneficiaryToken, userID: beneficiary.counterpartyUserId)
            return .success(ResolvedRecipient(
                // Le jeton — seul identifiant que le prepare accepte.
                recipientID: beneficiary.beneficiaryToken,
                actor: FinancialActor(
                    actorID: beneficiary.counterpartyUserId ?? beneficiary.beneficiaryToken,
                    type: .user,
                    displayName: beneficiary.displayName ?? localName ?? "",
                    verification: .verified,
                    jurisdiction: beneficiary.country
                ),
                resolvedAt: FinanceCoreDates.parse(beneficiary.resolvedAt) ?? Date()
            ))
        }
    }

    // MARK: - §3.2 Prepare

    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> {
        // Aucun prepare sans droit d'écriture : session verrouillée, pays fermé
        // ou `PAYMENT_PREPARE` refusé ne partent pas sur le réseau (§1.1, §1.5).
        // La raison exacte est gardée pour l'écran ; la logique ne voit que le refus.
        let explanations = FinanceErrorExplanations.shared
        guard let status = await session.status() else {
            return .failure(explanations.refuse(.sessionUnavailable))
        }
        if let refusal = status.writeRefusal {
            return .failure(explanations.refuse(refusal))
        }
        // La devise est celle du serveur (§0.3.8) : CAD depuis un JWT BI ⇒ CF_003.
        let currency = status.currency ?? draft.currency

        let request = PrepareSendMoneyRequest(
            currency: currency,
            amountMinor: Self.minorUnits(draft.amount, currency: currency),
            channel: "MOBILE",
            deviceId: deviceID(),
            beneficiaryToken: draft.recipientID,
            conversationId: draft.conversationID.flatMap { $0.isEmpty ? nil : $0 },
            sourceWalletRef: draft.sourceID
        )

        // Une clé par prepare : réessayer au niveau réseau renvoie la même
        // requête, donc la même clé ; un nouveau devis est une nouvelle intention,
        // et une intention préparée non exécutée ne déplace rien.
        let idempotency = IdempotencyContext.new(deviceID: deviceID())
        switch await FinanceCoreError.capture({
            try await dataSource.prepareSendMoney(request, idempotency: idempotency)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let response):
            return await accept(response, correlationID: idempotency.correlationID)
        }
    }

    /// Ressert le devis préparé tant qu'il vaut, sans appel réseau : un
    /// `quote/refresh` invaliderait l'empreinte de la confirmation en cours.
    ///
    /// **Expiré seulement**, et pour un envoi : `POST /send-money/quote/refresh`
    /// (§3.2, `CF_029`) rend un nouveau devis sur le même FCO plutôt qu'un
    /// nouveau prepare. Le devis rendu est **à reconfirmer** : il remplace
    /// l'ancien dans la revue, il ne part pas de lui-même.
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        guard let intent = await prepared.intent(for: quote.reference.id) else { return .failure(.expired) }
        let stillValid = !intent.quote.isExpired() && intent.confirmationExpiresAt > Date()
        guard !stillValid else { return .success(intent.quote) }
        // Facture, QR, espèces… n'ont pas de refresh au contrat : un nouveau prepare.
        guard intent.operation == .sendMoney else { return .failure(.expired) }

        let explanations = FinanceErrorExplanations.shared
        guard let status = await session.status() else {
            return .failure(explanations.refuse(.sessionUnavailable))
        }
        if let refusal = status.writeRefusal {
            return .failure(explanations.refuse(refusal))
        }
        let request = RefreshQuoteRequest(financialIntentRef: quote.reference.id,
                                          conversationId: intent.conversationID,
                                          deviceId: deviceID())
        switch await FinanceCoreError.capture({ try await dataSource.refreshSendMoneyQuote(request) }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let response):
            return await accept(response, correlationID: quote.reference.correlationID)
        }
    }

    // MARK: - Permis — rendu par le prepare

    func issue(for snapshot: ConfirmationSnapshot, idempotency: IdempotencyContext,
               stepUp: StepUpAttestation?) async -> Result<ExecutionPermit, FinanceError> {
        guard let intent = await prepared.intent(for: snapshot.reference.id),
              intent.confirmationExpiresAt > Date() else { return .failure(.executionPermitExpired) }
        return .success(ExecutionPermit(
            permitID: intent.executionPermitID ?? intent.confirmationID,
            objectID: snapshot.reference.id,
            snapshotHash: snapshot.decisionHash,
            issuedAt: Date(),
            expiresAt: intent.confirmationExpiresAt
        ))
    }

    /// Le serveur consomme l'empreinte à l'execute ; ici, on l'oublie.
    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> {
        await prepared.consume(permit.objectID)
        return .success(())
    }

    // MARK: - §4 Payer une demande

    /// `POST /request-money/pay` — « ouvre un Send Money » (§4, §4.1).
    ///
    /// La réponse est un `PrepareSendMoneyResponse` : elle passe par la même
    /// acceptation qu'un prepare d'envoi, et le devis se confirme ensuite par
    /// le même execute. Mêmes gardes de session qu'un envoi — aucun devis sans
    /// droit d'écriture.
    func payRequest(_ requestRef: String, conversationID: String?,
                    amount: Decimal?, currency: String?) async -> Result<TransferQuote, FinanceError> {
        let explanations = FinanceErrorExplanations.shared
        guard let status = await session.status() else {
            return .failure(explanations.refuse(.sessionUnavailable))
        }
        if let refusal = status.writeRefusal {
            return .failure(explanations.refuse(refusal))
        }
        let serverCurrency = status.currency ?? currency
        let request = PayMoneyRequestRequest(
            requestRef: requestRef,
            conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
            amountMinor: amount.flatMap { amount in
                serverCurrency.map { Self.minorUnits(amount, currency: $0) }
            },
            currency: amount == nil ? nil : serverCurrency,
            channel: "MOBILE",
            deviceId: deviceID()
        )
        let idempotency = IdempotencyContext.new(deviceID: deviceID())
        switch await FinanceCoreError.capture({
            try await dataSource.payMoneyRequest(request, idempotency: idempotency)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let response):
            return await accept(response, correlationID: idempotency.correlationID)
        }
    }

    // MARK: - §4 Payer une part de partage

    /// `POST /split-bill/pay` — « UNE part = UN consentement ».
    ///
    /// Même réponse que `/request-money/pay`, donc même acceptation et même
    /// execute : le partage n'a pas de machine à part, il ouvre un Send Money
    /// pour la part de cette personne. Le total du partage ne part jamais.
    func paySplitShare(_ splitRef: String, conversationID: String?,
                       amount: Money?) async -> Result<TransferQuote, FinanceError> {
        let explanations = FinanceErrorExplanations.shared
        guard let status = await session.status() else {
            return .failure(explanations.refuse(.sessionUnavailable))
        }
        if let refusal = status.writeRefusal {
            return .failure(explanations.refuse(refusal))
        }
        let request = PaySplitShareRequest(
            splitRef: splitRef,
            conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
            amountMinor: amount?.minorUnits,
            currency: amount?.currency.code ?? status.currency,
            channel: "MOBILE",
            deviceId: deviceID()
        )
        let idempotency = IdempotencyContext.new(deviceID: deviceID())
        switch await FinanceCoreError.capture({
            try await dataSource.paySplitShare(request, idempotency: idempotency)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let response):
            return await accept(response, correlationID: idempotency.correlationID)
        }
    }

    // MARK: - Lecture du prepare

    private func accept(_ response: PrepareSendMoneyResponseDTO,
                        correlationID: CorrelationId) async -> Result<TransferQuote, FinanceError> {
        await FinanceQuoteAcceptance.accept(
            PreparedQuoteFields(
                financialIntentRef: response.financialIntentRef,
                conversationID: response.conversationId,
                status: response.status, processRequired: response.processRequired,
                currency: response.quote?.currency ?? response.currency,
                principalMinor: response.quote?.principalMinor ?? response.amountMinor,
                feeMinor: response.quote?.feeMinor, totalMinor: response.quote?.totalMinor,
                fxRate: response.quote?.fxRate,
                quoteID: response.quote?.quoteId, quoteExpiresAt: response.quote?.expiresAt,
                confirmation: response.confirmation,
                objectVersion: response.objectVersion, executionPermitID: response.executionPermitId,
                beneficiaryEligible: response.beneficiary?.eligible
            ),
            correlationID: correlationID,
            operation: .sendMoney,
            store: prepared
        )
    }

    /// Montant → unités mineures, selon l'exposant ISO de la devise.
    static func minorUnits(_ amount: Decimal, currency: String) -> Int64 {
        var value = amount
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        for _ in 0..<(currency.isEmpty ? 0 : formatter.maximumFractionDigits) { value *= 10 }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
