//
//  LiveFinanceAPIClient.swift
//  FeatureChat
//
//  Phase 2 — la carte FCO comme seule preuve, et le requery en cas de doute.
//

import Foundation
import WaanguCoreKit

// MARK: - Finalité déclarée par Chat Core

/// Mémorise les objets que Chat Core a déclarés **finaux** (`visualSuccessFinal`).
///
/// Chat Core ne signe pas ses cartes : son autorité est `visualSuccessFinal`,
/// servi sur HTTPS authentifié. Le garde de confirmation historique exige une
/// signature et une preuve de rail que ce backend n'émet pas — en fabriquer une
/// pour le satisfaire serait précisément inventer une preuve. Ce registre est
/// donc le seul chemin vers « vérifié » en mode réel.
actor FinanceCoreFinality {
    private var final: [String: Int?] = [:]

    func record(objectID: String, revision: Int?, isFinal: Bool) {
        if isFinal { final[objectID] = revision } else { final[objectID] = nil }
    }

    func clear() { final.removeAll() }

    /// `true` si la dernière lecture de cet objet — à cette révision — l'a déclaré final.
    func isFinal(objectID: String, revision: Int?) -> Bool {
        guard let recorded = final[objectID] else { return false }
        guard let recorded, let revision else { return true }
        return revision <= recorded
    }
}

/// Garde de confirmation du mode réel : n'accepte qu'un succès déclaré final par Chat Core.
struct ChatCoreConfirmationGuard: PaymentConfirmationGuardProtocol {
    let finality: FinanceCoreFinality

    func decide(on confirmation: PaymentConfirmation) async -> PaymentConfirmationDecision {
        guard confirmation.status == .completed || confirmation.status == .confirmed else {
            return .undetermined(.statusNotFinal(confirmation.status))
        }
        let declared = await finality.isFinal(objectID: confirmation.reference.id,
                                              revision: confirmation.reference.version)
        return declared ? .accepted : .undetermined(.unverifiedSignature)
    }
}

// MARK: - Carte → enveloppe

enum FcoCardMapper {

    /// Statut de paiement d'une carte.
    ///
    /// Vocabulaire du backend Finance (`publicStatus` / `paymentStatus`) : PENDING,
    /// AUTHORIZATION, RISK_CHECKING, TO_ORCHESTRATOR, SENT_TO_SWITCH, ACCEPTED,
    /// SETTLED, FAILED, REVERSED, DISPUTED, EXPIRED, RECONCILIATION_REQUIRED,
    /// COMPLIANCE_HOLD, RESERVED, POSTED, REFUNDED, IN_DOUBT, REJECTED, UNKNOWN —
    /// plus les mots du contrat que le serveur envoie aussi (READY_FOR_CONFIRMATION,
    /// AWAITING_INPUT, SUBMITTED, PROCESSING, COMPLETED, CANCELLED).
    ///
    /// Seuls les mots du contrat étaient lus : `PENDING` et `SETTLED`, entre
    /// autres, tombaient sur `unknown` — un paiement en cours s'affichait
    /// « Vérification », un paiement réglé ne s'affichait jamais réussi.
    ///
    /// **Un règlement sans `visualSuccessFinal` n'est pas un succès** : il devient
    /// « en attente de rapprochement ». Un mot inconnu reste `unknown` — jamais
    /// un succès (le backend : « Unknown Finance vocabulary — never COMPLETED »).
    static func status(of card: FcoClientCardDTO) -> PaymentStatus {
        let status = paymentStatus(card.publicStatus ?? card.paymentStatus)
        guard status == .completed else { return status }
        return card.visualSuccessFinal == true ? .completed : .pendingReconciliation
    }

    /// Le même vocabulaire, pour qui n'a pas de carte.
    ///
    /// Les overlays l'emploient mot pour mot — `/top-up/requery` rend un
    /// `paymentStatus` de cette liste (§5.3.1). Le décoder par valeur brute
    /// ferait tomber `SUBMITTED` et `SETTLED` sur `unknown`, c'est-à-dire
    /// afficher « on ne sait pas » d'une recharge en vol ou réglée.
    ///
    /// Rend `.completed` pour un règlement : c'est à l'appelant qui possède
    /// `visualSuccessFinal` de le rétrograder, et à lui seul.
    static func paymentStatus(_ raw: String?) -> PaymentStatus {
        switch raw?.uppercased() {
        // Avant exécution.
        case "DRAFT", "CREATED", "READY_FOR_CONFIRMATION", "AWAITING_INPUT", "PENDING":
            return .pending
        case "SUBMITTED":
            return .queued
        // En cours chez Finance.
        case "PROCESSING", "AUTHORIZATION", "RISK_CHECKING", "TO_ORCHESTRATOR":
            return .processing
        case "RESERVED":
            return .authorized
        case "SENT_TO_SWITCH":
            return .pendingProvider
        case "ACCEPTED":
            return .pendingSettlement
        // Réglé. Le succès visuel reste conditionné à `visualSuccessFinal`,
        // vérifié par ``status(of:)`` — ici, le mot seul.
        case "COMPLETED", "SETTLED", "POSTED":
            return .completed
        case "RECONCILIATION_REQUIRED":
            return .pendingReconciliation
        case "COMPLIANCE_HOLD":
            return .complianceHold
        // Issues.
        case "FAILED":           return .failed
        case "REJECTED":         return .denied
        case "CANCELLED":        return .cancelled
        case "EXPIRED":          return .expired
        case "REVERSED":         return .reversed
        case "REFUNDED":         return .refunded
        case "DISPUTED":         return .disputed
        // Doute : requery, jamais un nouvel execute.
        case "IN_DOUBT":
            return .inDoubt
        case "UNKNOWN":
            return .unknown
        default:
            return .unknown
        }
    }

    /// Le sort d'une opération livrée par un tiers — recharge, facture : le
    /// débit **et** la livraison.
    ///
    /// Un paiement abouti que le fournisseur n'a pas livré n'est pas un succès
    /// (`TOPUP_NOT_DELIVERED`, `BILLER_NOT_UPDATED` des litiges) : il devient
    /// « en attente de rapprochement », comme un `COMPLETED` sans
    /// `visualSuccessFinal` sur une carte (``status(of:)``).
    ///
    /// Une valeur de livraison que ce client ne connaît pas n'est pas une
    /// livraison : rien n'autorise à la lire comme telle.
    static func overlayStatus(payment: String?, fulfillment: String?,
                              delivery: String?) -> PaymentStatus {
        let status = paymentStatus(payment)
        guard status == .completed || status == .confirmed else { return status }
        return delivered(fulfillment: fulfillment, delivery: delivery) ? status : .pendingReconciliation
    }

    /// Le fournisseur a-t-il livré ? `fulfillmentStatus` d'abord — c'est celui
    /// que le contrat renseigne — `deliveryStatus` ensuite.
    private static func delivered(fulfillment: String?, delivery: String?) -> Bool {
        let states = [fulfillment, delivery].compactMap { $0?.uppercased() }
        return states.contains { $0 == "DELIVERED" || $0 == "COMPLETED" || $0 == "FULFILLED" }
    }

    static func envelope(from card: FcoClientCardDTO) -> PaymentEnvelope {
        let currency = card.currency ?? ""
        let revision = FinanceCoreRevision.parse(card.objectVersion)
        return PaymentEnvelope(
            id: card.objectId,
            paymentType: card.operationKind == "SEND_MONEY" ? .p2p : .mobileWallet,
            amount: amount(minor: card.amountMinor ?? 0, currency: currency),
            currency: currency,
            timestamp: FinanceCoreDates.parse(card.updatedAt) ?? Date(),
            status: status(of: card),
            senderId: "", recipientId: "", merchantId: nil,
            // Aucune signature n'est inventée : Chat Core n'en émet pas.
            backendSignature: "",
            railProof: RailProof(railProvider: "", railTransactionId: "", railSignature: "",
                                 railTimestamp: .distantPast, railStatus: "", railMetadata: [:]),
            evidenceRefs: [],
            // Rang numérique, pour la garde de version du magasin. Illisible ⇒ brut,
            // donc sans révision exploitable : rien n'est fabriqué.
            version: revision.map(String.init) ?? (card.objectVersion ?? ""),
            idempotencyKey: "", correlationId: "",
            description: nil,
            metadata: [
                "publicStatus": card.publicStatus ?? "",
                "visualTone": card.visualTone ?? "",
                "fulfillmentStatus": card.fulfillmentStatus ?? "",
                "allowedActions": (card.allowedActions ?? []).joined(separator: ","),
            ],
            feeAmount: nil, feeCurrency: nil, exchangeRate: nil, crossBorder: false
        )
    }

    /// Unités mineures → montant, selon l'exposant ISO 4217 de la devise.
    static func amount(minor: Int64, currency: String) -> Decimal {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let exponent = currency.isEmpty ? 0 : formatter.maximumFractionDigits
        var value = Decimal(minor)
        for _ in 0..<exponent { value /= 10 }
        return value
    }
}

// MARK: - Client

/// `FinanceAPIClientProtocol` servi par Chat Core.
///
/// - Lecture : `GET /financial/objects/{ref}?reasonForAccess=SELF`.
/// - Doute : si la carte est `IN_DOUBT`, `POST /financial/intent/requery`, puis
///   relecture — **jamais** un nouvel execute (§9).
/// - Confirmation : `POST /financial/{operation}/execute`, sur le prepare
///   gardé par `PreparedIntentStore`. Création directe : fermée — le
///   parcours passe par le prepare.
struct LiveFinanceAPIClient: FinanceAPIClientProtocol {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let finality: FinanceCoreFinality
    let capabilitiesProvider: @Sendable () async -> FinanceCapabilities
    var prepared: PreparedIntentStore? = nil
    var deviceID: @Sendable () -> String = { "" }
    /// État de session au moment de l'execute. `nil` ⇒ refusé : par défaut,
    /// aucun execute ne part sans une session qui l'autorise.
    var sessionStatus: @Sendable () async -> FinanceSessionStatus? = { nil }
    /// Partagé avec `LiveMoneyRequestResponder` : une demande lue par la carte
    /// n'est pas relue par le magasin dans la même seconde.
    var requestReads: MoneyRequestReadCache? = nil

    func capabilities() async throws -> FinanceCapabilities {
        await capabilitiesProvider()
    }

    func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope {
        try await read(reference)
    }

    func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        if reference.type == .moneyRequest { return try await readRequest(reference) }
        var card = try await card(reference.id)
        if (card.publicStatus ?? card.paymentStatus) == "IN_DOUBT", let conversationID = card.conversationId {
            // Le requery interroge Finance ; son résultat se lit ensuite sur la carte.
            let request = RequeryIntentRequest(financialIntentRef: reference.id, conversationId: conversationID)
            if (try? await dataSource.requery(request, correlationID: reference.correlationID)) != nil {
                card = try await self.card(reference.id)
            }
        }
        return await record(card)
    }

    func createPaymentIntent(_ request: CreatePaymentIntentRequest,
                             idempotency: IdempotencyContext) async throws -> PaymentEnvelope {
        throw FinanceError.capabilityUnavailable
    }

    /// `POST /intent/cancel-request` (§10). Avant soumission : annulé. Après :
    /// `CF_046`, demandé seulement — Finance tranche.
    func cancelIntent(_ reference: FinancialReference,
                      conversationID: String?) async throws -> MoneyRequestCancelOutcome {
        let request = CancelIntentRequest(financialIntentRef: reference.id,
                                          conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
                                          reason: "user_abort")
        switch await FinanceCoreError.capture({
            try await dataSource.cancelRequest(request, correlationID: reference.correlationID)
        }) {
        case .success:
            return .cancelled
        case .failure(.business(let code, _)) where code.rawValue == "CF_046":
            return .requested
        case .failure(let error):
            throw error.financeError
        }
    }

    /// Execute — §3.3. **Jamais rejoué** : l'endpoint le déclare non idempotent,
    /// et l'empreinte est oubliée dès l'envoi, quelle qu'en soit l'issue.
    func confirmPaymentIntent(reference: FinancialReference, idempotency: IdempotencyContext,
                              stepUp: StepUpAttestation?) async throws -> PaymentEnvelope {
        guard let prepared, let intent = await prepared.intent(for: reference.id) else {
            // Aucun prepare vivant : il faut en refaire un, pas exécuter à l'aveugle.
            throw FinanceError.executionPermitExpired
        }
        // `PAYMENT_CONFIRM` refusé, session verrouillée depuis le prepare, pays
        // fermé : l'execute ne part pas. Le prepare reste gardé — il redevient
        // confirmable si la session est revalidée avant son expiration.
        let explanations = FinanceErrorExplanations.shared
        guard let status = await sessionStatus() else {
            throw explanations.refuse(.sessionUnavailable)
        }
        if let refusal = status.confirmRefusal {
            throw explanations.refuse(refusal)
        }
        let request = ExecuteIntentRequest(
            financialIntentRef: reference.id,
            confirmationId: intent.confirmationID,
            quoteId: intent.quoteID,
            deviceId: deviceID(),
            conversationId: intent.conversationID,
            objectVersion: intent.objectVersion,
            executionPermitId: intent.executionPermitID
        )

        let result = await FinanceCoreError.capture {
            try await dataSource.execute(intent.operation, request, correlationID: idempotency.correlationID)
        }
        await prepared.consume(reference.id)

        let response: ConfirmFinancialIntentResponseDTO
        switch result {
        case .success(let value):
            response = value
        case .failure(let failure):
            // Refus métier : le serveur a répondu, donc il n'a pas exécuté.
            // Le dire ici évite que l'écran présente un refus comme une issue
            // inconnue — et qu'une carte parte dans la conversation.
            if case .business = failure, let refusal = FinanceServerRefusal.decided(failure.financeError) {
                throw refusal
            }
            throw failure.financeError
        }
        // Accepté mais d'issue incertaine : requery, jamais un second execute — §9.
        if response.status == "IN_DOUBT" { throw FinanceError.timeoutUnknown }

        // Preuve d'écran : la carte. Illisible ⇒ l'état rendu par l'execute, jamais un succès.
        if let envelope = try? await read(reference) { return envelope }
        return FcoCardMapper.envelope(from: FcoClientCardDTO(
            objectId: reference.id, schemaVersion: nil, objectVersion: intent.objectVersion,
            publicStatus: response.status, visualTone: nil, visualSuccessFinal: false,
            intentType: response.intentType, operationKind: "SEND_MONEY",
            conversationId: response.conversationId ?? intent.conversationID,
            amountMinor: nil, currency: intent.quote.currency, paymentStatus: response.status,
            fulfillmentStatus: nil, deliveryStatus: nil, settlementStatus: nil,
            reconciliationStatus: nil, allowedActions: nil, financialActionsLocked: nil, updatedAt: nil
        ))
    }

    // MARK: -

    private func read(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        if reference.type == .moneyRequest { return try await readRequest(reference) }
        return await record(try await card(reference.id))
    }

    /// Une demande n'est pas une carte FCO : `GET /request-money/{requestRef}` — §4.
    private func readRequest(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        let dataSource = dataSource
        let ref = reference.id
        switch await FinanceCoreError.capture({
            if let requestReads {
                return try await requestReads.read(ref) { try await dataSource.moneyRequest(ref: ref) }
            }
            return try await dataSource.moneyRequest(ref: ref)
        }) {
        case .failure(let error):
            throw error.financeError
        case .success(let request):
            // `COMPLETED` d'une demande est l'état que le serveur publie — le seul
            // succès qu'on reprend, sous la même garde que les cartes.
            await finality.record(objectID: request.requestRef, revision: nil,
                                  isFinal: request.status == "COMPLETED")
            return RequestViewMapper.envelope(from: request)
        }
    }

    private func card(_ id: String) async throws -> FcoClientCardDTO {
        switch await FinanceCoreError.capture({ try await dataSource.financialObject(ref: id) }) {
        case .success(let card):  return card
        case .failure(let error): throw error.financeError
        }
    }

    private func record(_ card: FcoClientCardDTO) async -> PaymentEnvelope {
        await finality.record(objectID: card.objectId,
                              revision: FinanceCoreRevision.parse(card.objectVersion),
                              isFinal: card.visualSuccessFinal == true)
        return FcoCardMapper.envelope(from: card)
    }
}
