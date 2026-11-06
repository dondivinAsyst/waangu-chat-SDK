//
//  LiveSplitBillManaging.swift
//  FeatureChat
//
//  Partage d'addition — INTEGRATION_CHAT_FINANCE.md §4.
//

import Foundation
import WaanguCoreKit

/// `SplitBillManaging` servi par Chat Core.
///
/// Le contrat publie **trois** routes, et pas une de plus :
///
/// ```
/// POST /financial/split-bill          N parts, somme exacte — CF_041
/// GET  /financial/split-bill/{splitRef}
/// POST /financial/split-bill/pay      UNE part = UN consentement
/// ```
///
/// Tout le reste du protocole — la liste des partages, la réponse d'un
/// participant, la relance, la clôture — n'a **aucune route**. Ces méthodes
/// restent donc fermées plutôt que repliées sur un appel approchant : un
/// `respond` câblé sur `/split-bill` créerait un second partage au lieu
/// d'accepter le premier.
///
/// Des trois routes, une seule a sa réponse publiée : `/pay`, qui rend un
/// `PrepareSendMoneyResponse` (§3.2). Les deux autres sont appelées pour de
/// vrai et journalisées en DEBUG (`[FinanceSplit]`), comme l'ont été le
/// catalogue facturier et `qr/parse`, puis cartographiées une fois lues. D'ici
/// là l'écran dit « indisponible » — jamais un partage inventé par l'app.
struct LiveSplitBillManaging: SplitBillManaging {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let sendMoney: LiveSendMoney
    let deviceID: @Sendable () -> String

    // MARK: - Créer

    func create(_ draft: SplitBillDraft,
                idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> {
        let shares = Self.shares(of: draft)
        if let refusal = await checkArithmetic(total: draft.total.minorUnits, shares: shares) {
            return .failure(refusal)
        }
        let request = CreateSplitBillRequest(
            conversationId: draft.conversationID.flatMap { $0.isEmpty ? nil : $0 },
            label: draft.labelKey,
            currency: draft.total.currency.code,
            totalMinor: draft.total.minorUnits,
            strategy: Self.strategyCode(draft.strategy),
            privacyScope: draft.privacyScope.rawValue,
            shares: shares
        )
        switch await FinanceCoreError.capture({
            try await dataSource.createSplitBill(request, idempotency: idempotency)
        }) {
        case .failure(let error):
            // `CF_041` : la somme des parts ne fait pas le total.
            #if DEBUG
            print("[FinanceSplit] create failed: \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let view):
            return .success(Self.split(from: view, draft: draft))
        }
    }

    // MARK: - Lire

    func split(id: String) async -> Result<SplitBill, FinanceError> {
        switch await FinanceCoreError.capture({
            try await dataSource.splitBill(ref: id)
        }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceSplit] read failed: \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let view):
            return .success(Self.split(from: view, draft: nil))
        }
    }

    // MARK: - Lecture de la réponse

    /// La réponse est un **`RequestView`** portant `kind: "SPLIT_BILL"` : un
    /// partage est une demande d'argent à plusieurs parts nommées, et c'est le
    /// même objet que `/request-money` rend.
    ///
    /// Le serveur **n'y renvoie pas** ce qu'on lui a confié du partage lui-même
    /// — ni `label`, ni `strategy`, ni `privacyScope`. Ce qui est connu vient
    /// donc du brouillon qui vient d'être envoyé, et d'une relecture ultérieure
    /// il ne reste rien : voilà pourquoi le titre d'un partage relu est vide.
    /// À faire échoir au serveur — ce sont ses données, pas les nôtres.
    static func split(from view: RequestViewDTO, draft: SplitBillDraft?) -> SplitBill {
        let currency = CurrencyCode(code: view.currency ?? draft?.total.currency.code ?? "",
                                    exponent: draft?.total.currency.exponent ?? 0)
        let parties = view.parties ?? []
        let participants = parties.map { party in
            SplitParticipant(
                userID: party.chatUserId,
                // Le serveur ne rend pas de nom : l'écran le résout par ses
                // contacts, il ne s'invente pas ici.
                displayName: "",
                share: Money(minorUnits: party.requestedMinor ?? 0, currency: currency),
                contributed: Money(minorUnits: party.paidMinor ?? 0, currency: currency),
                consent: consent(of: party.status))
        }
        // Somme de montants **rendus par le serveur**, party par party : le
        // §50 interdit de recomposer un total depuis des contributions locales,
        // pas d'additionner ce que le serveur vient d'affirmer. Il n'expose
        // aucun agrégat — à demander, pour ne pas additionner du tout.
        let collected = parties.reduce(Int64(0)) { $0 + ($1.paidMinor ?? 0) }
        return SplitBill(
            id: view.requestRef,
            labelKey: draft?.labelKey ?? "",
            organizerID: view.requesterUserId ?? "",
            conversationID: view.conversationId,
            total: Money(minorUnits: view.amountMinor ?? 0, currency: currency),
            collected: Money(minorUnits: collected, currency: currency),
            participants: participants,
            strategy: draft?.strategy ?? .equal,
            state: state(of: view.status),
            privacyScope: draft?.privacyScope ?? .ownShareOnly,
            // Le serveur ne publie pas de politique de relance pour un partage.
            reminderPolicy: SplitReminderPolicy(maxPerParticipant: 0, minimumInterval: 0),
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: FinanceCoreDates.parse(view.expiresAt))
    }

    /// `PENDING` · `PAID` · `DECLINED` — un état inconnu n'autorise aucun débit.
    static func consent(of status: String?) -> SplitParticipantConsent {
        switch (status ?? "").uppercased() {
        case "PENDING":            return .pending
        case "ACCEPTED", "PAID",
             "PAYMENT_SENT":       return .accepted
        case "DECLINED":           return .declined
        case "EXPIRED":            return .expired
        default:                   return .unknown
        }
    }

    /// L'état de la demande, lu comme celui du partage.
    static func state(of status: String?) -> SplitSettlementState {
        switch (status ?? "").uppercased() {
        case "OPEN":               return .open
        case "PARTIALLY_PAID":     return .partiallySettled
        case "COMPLETED", "PAID":  return .settled
        case "CANCELLED":          return .cancelled
        case "EXPIRED":            return .expired
        default:                   return .unknown
        }
    }

    // MARK: - Payer sa part

    /// La seule route dont la réponse est publiée, et la seule qui déplace de
    /// l'argent — après devis et confirmation explicite, jamais ici.
    func payShare(splitID: String, conversationID: String?, amount: Money?,
                  idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        await sendMoney.paySplitShare(splitID, conversationID: conversationID, amount: amount)
    }

    // MARK: - Sans route

    /// Le contrat ne publie **aucune** route de liste — comme pour le relevé.
    ///
    /// Le dire par ce drapeau, et non par un `capabilityUnavailable` : ce code
    /// affirme « votre compte n'y a pas droit », ce que seul le serveur peut
    /// établir, et il venait justement d'accorder `SPLIT_BILL`. L'écran lisait
    /// donc à l'utilisateur le contraire de ce que la source de vérité disait.
    var listsSplits: Bool { false }

    func splits(cursor: String?) async -> Result<[SplitBill], FinanceError> {
        .success([])
    }

    func respond(splitID: String, response: SplitParticipantResponse,
                 idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// **Jamais un débit direct.** Le paiement passe par ``payShare`` : devis,
    /// puis confirmation humaine, puis execute — §4 et §0.3.1.
    func contribute(splitID: String, amount: Money, idempotency: IdempotencyContext,
                    stepUp: StepUpAttestation?) async -> Result<SplitBill, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func remind(splitID: String, participantID: String,
                idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func close(splitID: String,
               idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    // MARK: - Répartition

    /// Les parts font-elles le total ? Demandé à la calculette du serveur
    /// (`POST /pay-bill/split`, §5.1.2) plutôt qu'à une addition locale : la
    /// division est faite ici, c'est au serveur de dire qu'elle tombe juste.
    ///
    /// Un refus net (`valid=false`, `CF_041`) arrête la création — rien n'a été
    /// créé. Une calculette injoignable ne bloque rien : la création elle-même
    /// refuse un total faux, et elle seule fait foi.
    private func checkArithmetic(total: Int64, shares: [SplitShareRequest]) async -> FinanceError? {
        let request = PayBillSplitRequest(totalMinor: total, parts: shares.map(\.amountMinor))
        let mismatch = FinanceCoreErrorCode(rawValue: "CF_041")
        switch await FinanceCoreError.capture({ try await dataSource.billSplitCheck(request) }) {
        case .success(let result):
            return result.valid == false ? mismatch.financeError : nil
        case .failure(.business(let code, _)) where code == mismatch:
            return code.financeError
        case .failure(let error):
            #if DEBUG
            print("[FinanceSplit] split check unavailable, create decides: \(error)")
            #endif
            return nil
        }
    }

    static func strategyCode(_ strategy: SplitStrategy) -> String {
        switch strategy {
        case .equal:        return "EQUAL"
        case .custom:       return "CUSTOM"
        case .proportional: return "PROPORTIONAL"
        }
    }

    /// Les parts envoyées au serveur : une par participant, en unités mineures,
    /// **de somme exactement égale au total** (`CF_041` sinon).
    ///
    /// La route n'a pas de champ `strategy` : elle attend des montants, pas une
    /// intention. C'est donc le client qui divise — ce que le §50 réserve au
    /// serveur (« pas de recalcul financier définitif côté client »), et qui
    /// reste **à confirmer avec le backend**. Tant que la route est ainsi, il
    /// n'y a pas d'alternative : ne rien envoyer créerait un partage sans parts.
    static func shares(of draft: SplitBillDraft) -> [SplitShareRequest] {
        let currency = draft.total.currency.code
        switch draft.strategy {
        case .custom(let values):
            return draft.participantIDs.map {
                SplitShareRequest(userId: $0,
                                  amountMinor: LiveSendMoney.minorUnits(values[$0] ?? 0,
                                                                        currency: currency))
            }
        case .proportional(let weights):
            return distribute(draft.total.minorUnits,
                              over: draft.participantIDs,
                              weights: draft.participantIDs.map { weights[$0] ?? 0 })
        case .equal:
            return distribute(draft.total.minorUnits,
                              over: draft.participantIDs,
                              weights: draft.participantIDs.map { _ in 1 })
        }
    }

    /// Répartit un total au prorata, **sans jamais perdre ni créer d'unité**.
    ///
    /// Le reste d'une division inexacte doit tomber quelque part : 500 sur
    /// trois fait 166, 166, 166 — et deux unités s'évaporeraient. Elles vont
    /// aux **premiers** participants, une chacune, et la somme retombe juste.
    /// C'est `SplitRoundingPolicy.distributed`, appliquée ici faute de pouvoir
    /// la déléguer.
    static func distribute(_ total: Int64, over participants: [String],
                           weights: [Decimal]) -> [SplitShareRequest] {
        guard !participants.isEmpty else { return [] }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return [] }

        var amounts = weights.map { weight -> Int64 in
            let share = (Decimal(total) * weight) / sum
            var floored = Decimal()
            var value = share
            NSDecimalRound(&floored, &value, 0, .down)
            return NSDecimalNumber(decimal: floored).int64Value
        }
        var remainder = total - amounts.reduce(0, +)
        var index = 0
        while remainder > 0, index < amounts.count {
            amounts[index] += 1
            remainder -= 1
            index += 1
        }
        return zip(participants, amounts).map { SplitShareRequest(userId: $0, amountMinor: $1) }
    }
}
