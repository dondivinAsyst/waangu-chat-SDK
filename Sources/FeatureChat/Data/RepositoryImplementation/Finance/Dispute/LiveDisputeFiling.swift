//
//  LiveDisputeFiling.swift
//  FeatureChat
//
//  Phase 10 — ouvrir un litige sur Chat Core.
//

import Foundation
import WaanguCoreKit

/// `DisputeFiling` sur Chat Core : `POST /disputes`, puis la description versée
/// en note (`POST /disputes/{id}/evidence`) — le corps d'ouverture n'a pas de
/// champ texte.
///
/// La catégorie vient de la taxonomie du serveur. Les motifs de l'écran sont
/// rapprochés de ses catégories ; un rapprochement que le serveur ne liste pas
/// devient `OTHER` plutôt qu'un `CF_048`.
struct LiveDisputeFiling: DisputeFiling {

    let dataSource: any RemoteChatFinanceDataSourceProtocol

    func file(_ draft: DisputeDraft,
              idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError> {
        // Le consentement conditionne le dépôt : le dossier peut partir chez un tiers.
        guard draft.sharingConsent else { return .failure(.validation(field: "sharingConsent")) }

        let taxonomy: Set<String>
        switch await FinanceCoreError.capture({ try await dataSource.disputeTaxonomy() }) {
        case .success(let categories): taxonomy = Set(categories)
        case .failure(let error):      return .failure(error.financeError)
        }

        // La catégorie choisie dans la taxonomie du serveur part telle quelle ;
        // hors taxonomie, c'est `CF_048` que le serveur rendrait — refusé avant l'envoi.
        let category: String
        if let chosen = draft.category {
            guard taxonomy.contains(chosen) else { return .failure(.validation(field: "category")) }
            category = chosen
        } else if let reason = draft.reason {
            category = Self.category(for: reason, objectType: draft.reference.type, in: taxonomy)
        } else {
            return .failure(.validation(field: "category"))
        }
        let request = OpenDisputeRequest(
            conversationId: draft.conversationID.flatMap { $0.isEmpty ? nil : $0 },
            financialIntentRef: draft.reference.id,
            category: category,
            // La priorité appartient au serveur : le client ne la décide pas.
            priority: nil)
        let opened: DisputeCaseDTO
        switch await FinanceCoreError.capture({ try await dataSource.openDispute(request) }) {
        case .success(let value): opened = value
        case .failure(let error): return .failure(error.financeError)
        }

        let reference = FinancialReference(type: .dispute, id: opened.disputeId,
                                           version: 1, correlationID: draft.correlationID)
        let text = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .success(reference) }
        // Le litige existe : une note qui échoue ne l'annule pas, et le
        // signaler comme un échec ferait ouvrir un second dossier.
        let note = DisputeEvidenceRequest(type: "NOTE", content: text, visibility: "SUPPORT_ONLY")
        if case .failure(let error) = await FinanceCoreError.capture({
            try await dataSource.addDisputeEvidence(disputeID: opened.disputeId, note)
        }) {
            #if DEBUG
            print("[FinanceDispute] note not attached to \(opened.disputeId): \(error)")
            #endif
        }
        return .success(reference)
    }

    /// Le serveur ne reçoit que des notes en JSON (§10) : du texte, rien d'autre.
    func allowedEvidence(for reason: DisputeReason) async -> Result<[EvidenceKind], FinanceError> {
        .success([.text])
    }

    func categories() async -> Result<[String], FinanceError> {
        switch await FinanceCoreError.capture({ try await dataSource.disputeTaxonomy() }) {
        case .success(let categories): return .success(categories)
        case .failure(let error):      return .failure(error.financeError)
        }
    }

    /// `GET /disputes/{id}` puis `/timeline`. La frise manquante n'empêche pas
    /// de montrer le dossier : le statut est ce qui compte.
    func follow(disputeID: String) async -> Result<DisputeStatusSnapshot, FinanceError> {
        let dispute: DisputeCaseDTO
        switch await FinanceCoreError.capture({ try await dataSource.dispute(id: disputeID) }) {
        case .success(let value): dispute = value
        case .failure(let error): return .failure(error.financeError)
        }
        var steps: [DisputeTimelineStep] = []
        if case .success(let rows) = await FinanceCoreError.capture({ try await dataSource.disputeTimeline(id: disputeID) }) {
            steps = rows.map { DisputeTimelineStep(step: $0.step, value: $0.value) }
        }
        return .success(DisputeStatusSnapshot(
            disputeID: dispute.disputeId, status: dispute.status ?? "",
            category: dispute.category, priority: dispute.priority,
            firstResponseDueAt: FinanceCoreDates.parse(dispute.firstResponseDueAt),
            resolveDueAt: FinanceCoreDates.parse(dispute.resolveDueAt),
            closedAt: FinanceCoreDates.parse(dispute.closedAt),
            timeline: steps))
    }

    /// Motif de l'écran → catégorie de la taxonomie serveur.
    static func category(for reason: DisputeReason, objectType: FinancialObjectType,
                         in taxonomy: Set<String>) -> String {
        let wanted: String
        switch reason {
        case .fraud, .unknownPayment: wanted = "UNRECOGNIZED_PAYMENT"
        case .wrongRecipient:         wanted = "WRONG_BENEFICIARY"
        case .serviceNotDelivered:    wanted = "SERVICE_NOT_DELIVERED"
        case .rechargeIssue:          wanted = "TOPUP_NOT_DELIVERED"
        case .duplicateDebit:         wanted = "DOUBLE_DEBIT"
        case .billIssue:              wanted = "BILLER_NOT_UPDATED"
        case .cashIssue:
            switch objectType {
            case .cashIn:  wanted = "CASH_RECEIVED_NOT_CREDITED"
            case .cashOut: wanted = "CASHOUT_NOT_REMITTED"
            default:       wanted = "OTHER"
            }
        case .wrongAmount, .merchantIssue:
            wanted = "OTHER"
        }
        return taxonomy.contains(wanted) ? wanted : "OTHER"
    }
}
