//
//  LiveMoneyRequests.swift
//  FeatureChat
//
//  Phase 4 — Request Money sur Chat Core (INTEGRATION_CHAT_FINANCE.md §4).
//

import Foundation
import WaanguCoreKit

/// Correspondances apprises auprès du serveur, jamais devinées.
///
/// - Jeton de bénéficiaire → utilisateur Chat : la résolution rend les deux.
///   Send Money prend le jeton ; Request Money exige l'utilisateur Chat (§4 :
///   « parties = userIds Chat »).
/// - Demande → parties : la relance nomme la partie relancée.
actor FinanceCoreDirectory {
    private var userIDByToken: [String: String] = [:]
    private var partiesByRequest: [String: [String]] = [:]

    func remember(token: String, userID: String?) {
        guard let userID, !userID.isEmpty else { return }
        userIDByToken[token] = userID
    }

    func userID(forToken token: String) -> String? { userIDByToken[token] }

    func remember(request: String, parties: [String]) { partiesByRequest[request] = parties }

    func parties(of request: String) -> [String] { partiesByRequest[request] ?? [] }

    func clear() {
        userIDByToken.removeAll()
        partiesByRequest.removeAll()
    }
}

/// `MoneyRequestCreating` servi par Chat Core.
struct LiveMoneyRequests: MoneyRequestCreating {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let directory: FinanceCoreDirectory
    let session: FinanceCoreSessionRepository

    /// Les bornes anti-abus sont **serveur** : relance limitée (CF_035), demande
    /// refusée (CF_034), capacité fermée (CF_005). Le client ne les recopie pas —
    /// une borne locale divergerait de celle du serveur au premier réglage. Il
    /// ne refuse donc rien d'avance, et affiche le refus quand il arrive.
    func policy(towards recipientID: String) async -> Result<MoneyRequestPolicy, FinanceError> {
        .success(MoneyRequestPolicy(
            maxRemindersPerRequest: .max, minIntervalBetweenReminders: 0,
            maxOpenRequestsPerRecipient: .max, allowsRequestToNonContacts: true,
            recipientHasBlockedSender: false
        ))
    }

    func createRequest(_ draft: MoneyRequestDraft,
                       idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError> {
        // L'utilisateur Chat rendu par la résolution fait foi ; l'interlocuteur
        // de la conversation n'est qu'un repli, pour une résolution qui a
        // trouvé le compte sans nommer son utilisateur Chat.
        let resolvedUserID = await directory.userID(forToken: draft.recipientID)
        guard let userID = resolvedUserID ?? draft.recipientChatUserID.flatMap({ $0.isEmpty ? nil : $0 }) else {
            // Sans utilisateur Chat connu, rien ne part : un identifiant de partie
            // Finance ou un nom à la place serait refusé, ou pire, accepté à tort.
            //
            // `undetermined`, pas `notFound` : la résolution **a** trouvé le
            // compte. Écrire « aucun compte ne correspond » était faux, et
            // poussait à ressaisir un bénéficiaire correct.
            #if DEBUG
            print("[FinanceRequest] no chat userId for beneficiary token — resolve-beneficiary "
                  + "returned no counterpartyUserId and no conversation peer; nothing sent")
            #endif
            return .failure(.recipientUnresolved(reason: .undetermined))
        }
        #if DEBUG
        if resolvedUserID == nil {
            print("[FinanceRequest] resolve-beneficiary returned no counterpartyUserId — "
                  + "using the conversation peer's chat userId")
        }
        #endif

        let currency: String
        if case .success(let snapshot) = await session.current(),
           let serverCurrency = snapshot.experience.currency ?? snapshot.governance.currency {
            currency = serverCurrency
        } else {
            currency = draft.currency
        }

        let request = CreateMoneyRequestRequest(
            recipientUserIds: [userID],
            amountMode: draft.amount == nil ? "FREE" : "FIXED",
            currency: currency,
            amountMinor: draft.amount.map { LiveSendMoney.minorUnits($0, currency: currency) },
            conversationId: draft.conversationID.flatMap { $0.isEmpty ? nil : $0 },
            note: draft.note
        )

        switch await FinanceCoreError.capture({
            try await dataSource.createMoneyRequest(request, idempotency: idempotency)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let request):
            await directory.remember(request: request.requestRef,
                                     parties: request.parties?.map(\.chatUserId) ?? [userID])
            // Aucune révision n'est publiée par `RequestView` : 0, que la première
            // révision serveur (pointeur MQTT) remplacera.
            return .success(FinancialReference(type: .moneyRequest, id: request.requestRef,
                                               version: 0, correlationID: idempotency.correlationID))
        }
    }

    func remind(_ reference: FinancialReference,
                idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        guard let party = await directory.parties(of: reference.id).first else {
            return .failure(.validation(field: "partyUserId"))
        }
        let request = RemindMoneyRequestRequest(requestRef: reference.id, partyUserId: party)
        switch await FinanceCoreError.capture({
            try await dataSource.remindMoneyRequest(request, correlationID: idempotency.correlationID)
        }) {
        case .success:            return .success(())
        case .failure(let error): return .failure(error.financeError)
        }
    }

    /// Le contrat §4 ne publie aucune annulation par le demandeur. Rien n'est
    /// simulé : l'action reste indisponible.
    func revoke(_ reference: FinancialReference,
                idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

// MARK: - Carte d'une demande

enum RequestViewMapper {

    static func status(of request: RequestViewDTO) -> PaymentStatus {
        switch request.status {
        case "OPEN":      return .pending
        case "EXPIRED":   return .expired
        case "CANCELLED": return .cancelled
        case "COMPLETED": return .completed
        default:          return .unknown
        }
    }

    static func envelope(from request: RequestViewDTO) -> PaymentEnvelope {
        let currency = request.currency ?? ""
        return PaymentEnvelope(
            id: request.requestRef, paymentType: .p2p,
            amount: FcoCardMapper.amount(minor: request.amountMinor ?? 0, currency: currency),
            currency: currency, timestamp: Date(), status: status(of: request),
            senderId: request.requesterUserId ?? "", recipientId: request.parties?.first?.chatUserId ?? "",
            merchantId: nil, backendSignature: "",
            railProof: RailProof(railProvider: "", railTransactionId: "", railSignature: "",
                                 railTimestamp: .distantPast, railStatus: "", railMetadata: [:]),
            evidenceRefs: [],
            // Pas de révision dans `RequestView` : on n'en invente aucune. Celle du
            // pointeur MQTT qui a déclenché la relecture fait foi.
            version: "",
            idempotencyKey: "", correlationId: "", description: request.note,
            metadata: ["amountMode": request.amountMode ?? ""],
            feeAmount: nil, feeCurrency: nil, exchangeRate: nil, crossBorder: false
        )
    }
}
