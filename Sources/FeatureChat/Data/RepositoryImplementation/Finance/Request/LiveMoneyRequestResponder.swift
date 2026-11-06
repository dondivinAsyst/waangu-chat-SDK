//
//  LiveMoneyRequestResponder.swift
//  FeatureChat
//
//  Phase 4 — répondre à une demande d'argent (INTEGRATION_CHAT_FINANCE.md §4).
//

import Foundation
import WaanguCoreKit

/// `MoneyRequestResponding` servi par Chat Core.
struct LiveMoneyRequestResponder: MoneyRequestResponding {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let sendMoney: LiveSendMoney
    /// Utilisateur Chat de la session — pour retrouver **sa** part.
    let currentUserID: @Sendable () -> String
    /// Lecture partagée avec le magasin — voir `MoneyRequestReadCache`.
    var reads: MoneyRequestReadCache? = nil

    func overlay(for reference: FinancialReference) async -> Result<MoneyRequestOverlay, FinanceError> {
        let dataSource = dataSource
        let ref = reference.id
        switch await FinanceCoreError.capture({
            if let reads {
                return try await reads.read(ref) { try await dataSource.moneyRequest(ref: ref) }
            }
            return try await dataSource.moneyRequest(ref: ref)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let request):
            return .success(Self.overlay(request, reference: reference, me: currentUserID()))
        }
    }

    /// Payer — sa part d'un partage, ou une demande ordinaire.
    ///
    /// Deux routes pour un même geste, et c'est la **nature de l'objet** qui
    /// tranche : un partage se paie par `/split-bill/pay`. Les deux rendent le
    /// même `PrepareSendMoneyResponse`, donc tout ce qui suit — devis,
    /// confirmation, execute — est identique.
    func pay(_ reference: FinancialReference, conversationID: String?,
             amount: Decimal?, currency: String?) async -> Result<TransferQuote, FinanceError> {
        await reads?.invalidate(reference.id)
        let overlay = await overlay(for: reference)
        if case .success(let request) = overlay, request.isSplitBill {
            return await sendMoney.paySplitShare(
                reference.id, conversationID: conversationID,
                amount: amount.map { Money(minorUnits: LiveSendMoney.minorUnits($0, currency: currency ?? request.currency),
                                           currency: CurrencyCode(code: currency ?? request.currency, exponent: 0)) })
        }
        return await sendMoney.payRequest(reference.id, conversationID: conversationID,
                                   amount: amount, currency: currency)
    }

    func decline(_ reference: FinancialReference, conversationID: String?) async -> Result<Void, FinanceError> {
        await reads?.invalidate(reference.id)
        let request = DeclineMoneyRequestRequest(
            requestRef: reference.id, conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 })
        switch await FinanceCoreError.capture({
            try await dataSource.declineMoneyRequest(request, correlationID: reference.correlationID)
        }) {
        case .success:            return .success(())
        case .failure(let error): return .failure(error.financeError)
        }
    }

    func remind(_ reference: FinancialReference, partyUserID: String) async -> Result<Void, FinanceError> {
        await reads?.invalidate(reference.id)
        let request = RemindMoneyRequestRequest(requestRef: reference.id, partyUserId: partyUserID)
        switch await FinanceCoreError.capture({
            try await dataSource.remindMoneyRequest(request, correlationID: reference.correlationID)
        }) {
        case .success:            return .success(())
        case .failure(let error): return .failure(error.financeError)
        }
    }

    func cancel(_ reference: FinancialReference,
                conversationID: String?) async -> Result<MoneyRequestCancelOutcome, FinanceError> {
        await reads?.invalidate(reference.id)
        let request = CancelIntentRequest(
            financialIntentRef: reference.id, conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 })
        switch await FinanceCoreError.capture({
            try await dataSource.cancelIntent(request, correlationID: reference.correlationID)
        }) {
        case .success:
            return .success(.cancelled)
        case .failure(.business(let code, _)) where code.rawValue == "CF_046":
            // 202 métier : la demande d'annulation est acceptée, pas encore faite.
            return .success(.requested)
        case .failure(let error):
            return .failure(error.financeError)
        }
    }

    func forget(_ reference: FinancialReference) async {
        await reads?.invalidate(reference.id)
    }

    // MARK: Lien de paiement — Phase 4

    func issueLink(for reference: FinancialReference,
                   conversationID: String?) async -> Result<MoneyRequestLink, FinanceError> {
        let request = IssuePaymentLinkRequest(requestRef: reference.id, conversationId: conversationID)
        let idempotency = IdempotencyContext.new(deviceID: sendMoney.deviceID())
        switch await FinanceCoreError.capture({
            try await dataSource.issuePaymentLink(request, idempotency: idempotency)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let link):
            // Une nouvelle action proposée (lien actif) : relire la demande.
            await reads?.invalidate(reference.id)
            return .success(MoneyRequestLink(
                token: link.token, nonce: link.nonce, requestRef: link.requestRef,
                conversationID: link.conversationId,
                expiresAt: FinanceCoreDates.parse(link.expiresAt),
                // Le contrat le fixe à `false` ; absent, il reste `false`.
                executable: link.executable ?? false,
                consumedAt: FinanceCoreDates.parse(link.consumedAt)))
        }
    }

    func inspectLink(token: String, nonce: String) async -> Result<MoneyRequestOverlay, FinanceError> {
        let request = InspectPaymentLinkRequest(token: token, nonce: nonce)
        switch await FinanceCoreError.capture({ try await dataSource.inspectPaymentLink(request) }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let raw):
            // La forme du contexte n'est pas publiée : on n'en lit que la demande
            // désignée, puis on lit la demande elle-même — forme connue.
            guard let requestRef = Self.requestRef(in: raw) else {
                #if DEBUG
                print("[FinanceLink] inspect returned no requestRef: \(LiveBillPaying.describe(raw))")
                #endif
                return .failure(.server(statusCode: nil))
            }
            return await overlay(for: FinancialReference(type: .moneyRequest, id: requestRef, version: 0,
                                                         correlationID: CorrelationId()))
        }
    }

    /// `requestRef` au premier niveau, ou dans un objet imbriqué (`link`,
    /// `request`, `paymentLink`…) : le premier trouvé.
    static func requestRef(in value: JSONValue) -> String? {
        guard case .dictionary(let object) = value else { return nil }
        if case .string(let ref)? = object["requestRef"], !ref.isEmpty { return ref }
        for key in object.keys.sorted() {
            if let nested = object[key], let ref = requestRef(in: nested) { return ref }
        }
        return nil
    }

    /// `RequestView` → ce que la demande dit à `me`.
    static func overlay(_ request: RequestViewDTO, reference: FinancialReference,
                        me: String) -> MoneyRequestOverlay {
        let currency = request.currency ?? ""
        let mine = request.parties?.first { $0.chatUserId == me }
        let pending = (request.parties ?? [])
            .filter { ($0.remainingMinor ?? 0) > 0 && $0.status?.uppercased() != "DECLINED" }
            .map(\.chatUserId)
        return MoneyRequestOverlay(
            reference: reference,
            status: RequestViewMapper.status(of: request),
            isRequester: !me.isEmpty && request.requesterUserId == me,
            amountMode: request.amountMode?.uppercased() == "FREE" ? .free : .fixed,
            currency: currency,
            requestedTotal: request.amountMinor.map { FcoCardMapper.amount(minor: $0, currency: currency) },
            myRemaining: mine?.remainingMinor.map {
                FcoCardMapper.amount(minor: $0, currency: mine?.currency ?? currency)
            },
            nextSafeActions: Set((request.nextSafeActions ?? []).map { $0.uppercased() }),
            pendingPartyUserIDs: pending,
            myPartyStatus: mine?.status,
            conversationID: request.conversationId,
            kind: request.kind
        )
    }
}
