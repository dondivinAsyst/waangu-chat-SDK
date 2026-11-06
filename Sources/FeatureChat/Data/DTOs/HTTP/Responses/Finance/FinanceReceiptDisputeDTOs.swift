//
//  FinanceReceiptDisputeDTOs.swift
//  FeatureChat
//
//  Phase 10 — reçus et litiges (missing-chat-finance-dtos.md).
//

import Foundation

/// `ReceiptRecord` — `POST /receipts/issue`, `/receipts/verify`, `/receipts/share`.
///
/// `signedUrl` n'est rempli que par `/receipts/share` : c'est Finance qui signe
/// l'URL (`CF_051` si Finance n'est pas câblé). Chat n'en fabrique jamais.
struct ReceiptRecordDTO: Decodable, Equatable, Sendable {
    let receiptRef: String
    let financialIntentRef: String?
    let conversationId: String?
    let sha256: String?
    let version: Int?
    let storageKey: String?
    let classification: String?
    let generatedAt: String?
    let signedUrl: String?
    let signedUrlExpiresAt: String?
}

/// Une preuve versée au dossier.
struct DisputeEvidenceDTO: Decodable, Equatable, Sendable {
    let evidenceId: String
    let type: String?
    let sha256: String?
    let malwareStatus: String?
    let visibility: String?
    let authorUserId: String?
    let createdAt: String?
}

/// `DisputeCase` — `POST /disputes`, `GET /disputes/{id}`, `/evidence`.
///
/// Le litige vit dans **un fil support isolé** (`supportConversationId`), pas
/// dans la conversation d'origine (`CF_049`).
struct DisputeCaseDTO: Decodable, Equatable, Sendable {
    let disputeId: String
    let conversationId: String?
    let supportConversationId: String?
    let financialIntentRef: String?
    let category: String?
    let priority: String?
    let status: String?
    let firstResponseDueAt: String?
    let resolveDueAt: String?
    let createdAt: String?
    let closedAt: String?
    let closeReason: String?
    let evidence: [DisputeEvidenceDTO]?
}

/// `POST /reversal/request` — une demande enregistrée (`REVERSAL_REQUESTED`).
struct ReversalRequestedDTO: Decodable, Equatable, Sendable {
    let originalIntentRef: String?
    let status: String?
    let message: String?
}

/// `GET /disputes/{id}/timeline` — une étape et sa valeur, telles que le serveur les rend.
struct DisputeTimelineStepDTO: Decodable, Equatable, Sendable {
    let step: String
    let value: String?
}

// MARK: - Phase 8 — traduction

/// `POST /hub/translation/mask` → `MaskedText`. `tokens` : jeton → valeur
/// retirée (montant, numéro…). Ce qui doit revenir intact après traduction.
struct MaskedTextDTO: Decodable, Equatable, Sendable {
    let original: String?
    let masked: String
    let tokens: [String: String]?
}

// MARK: - §5.2 — facture marchande

/// `POST /invoice/inquire` → `InvoiceOutstanding`. Le reste dû vient du
/// Merchant Backend : le client ne le calcule pas et ne l'envoie pas au prepare.
struct InvoiceOutstandingDTO: Decodable, Equatable, Sendable {
    let invoiceRef: String
    let merchantId: String?
    let storeId: String?
    let terminalId: String?
    let outstandingMinor: Int64?
    let paidMinor: Int64?
    let currency: String?
    /// `OPEN` · `PAID` · `VOID` · `PARTIAL`.
    let status: String?
    let expiresAt: String?
}

// MARK: - Phase 8 — Waangu Copilot

/// `GET /hub/copilot-tools` → `CopilotToolDefinition`.
struct CopilotToolDTO: Decodable, Equatable, Sendable {
    let name: String
    let domain: String?
    let version: String?
    let operation: String?
    let mutating: Bool?
    let requiresConfirmation: Bool?
    let requiresCompliance: Bool?
    let executeForbidden: Bool?
    let enabled: Bool?
    let description: String?
    let handoffAction: String?
}

/// `POST /hub/copilot-tools/invoke` → `ToolResult`. `executed` est **toujours**
/// `false` : un `true` est une violation du contrat, et refusé comme telle.
struct CopilotToolResultDTO: Decodable, Equatable, Sendable {
    let tool: String?
    let executed: Bool?
    let authoritative: Bool?
    let message: String?
    let nextSafeActions: [String]?
    let handoffAction: String?
    /// `{}` dans l'exemple du contrat : absent ou vide n'est pas un refus.
    let attributes: CopilotInvokeAttributesDTO?
}

/// Les garanties de la réponse. Un `false` explicite dit que le serveur ne
/// garantit plus une réponse de préparation seule.
struct CopilotInvokeAttributesDTO: Decodable, Equatable, Sendable {
    let draftOnly: Bool?
    let executeForbidden: Bool?
}
