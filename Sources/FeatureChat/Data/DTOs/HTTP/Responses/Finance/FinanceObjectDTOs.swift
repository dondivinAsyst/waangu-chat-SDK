//
//  FinanceObjectDTOs.swift
//  FeatureChat
//
//  Phase 2 — carte FCO et requery (INTEGRATION_CHAT_FINANCE.md §3.3, §7, §9).
//

import Foundation

// MARK: - §7 — GET /chat-core/financial/objects/{financialIntentRef}

/// `FcoClientCard` — **seule preuve UI** après execute ou pointeur MQTT.
struct FcoClientCardDTO: Decodable, Equatable, Sendable {
    let objectId: String
    let schemaVersion: String?
    /// Révision opaque (`v2-c0ff`) — à renvoyer à l'execute.
    let objectVersion: String?
    let publicStatus: String?
    /// `SUCCESS_FINAL` · `PENDING` · `FAILED` · `HOLD` · `CANCELLED` · `INFO`.
    let visualTone: String?
    /// `true` **uniquement** si Finance a confirmé `COMPLETED`.
    let visualSuccessFinal: Bool?
    let intentType: String?
    let operationKind: String?
    let conversationId: String?
    let amountMinor: Int64?
    let currency: String?
    let paymentStatus: String?
    let fulfillmentStatus: String?
    let deliveryStatus: String?
    let settlementStatus: String?
    let reconciliationStatus: String?
    let allowedActions: [String]?
    let financialActionsLocked: Bool?
    let updatedAt: String?
}

// MARK: - §3.3 / §9 — ConfirmFinancialIntentResponse (execute, requery)

struct ConfirmFinancialIntentResponseDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let intentType: String?
    /// `SUBMITTED` · `PROCESSING` · `COMPLIANCE_HOLD` · `IN_DOUBT` · … — jamais une preuve de succès.
    let status: String?
    let processRequired: Bool?
    let executionPermitId: String?
    let nextSafeActions: [String]?
    let confirmedAt: String?
}

// MARK: - Révision

/// Révision numérique d'un `objectVersion` opaque.
///
/// Le contrat renvoie `v1-a1b2`, `v2-c0ff` : un rang puis une empreinte. Le
/// magasin compare des entiers ; on lit le rang. Illisible ⇒ `nil`, et aucune
/// révision n'est inventée — le magasin refusera par égalité, ce qui est sûr.
enum FinanceCoreRevision {
    static func parse(_ value: String?) -> Int? {
        guard var text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let digits = text.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
