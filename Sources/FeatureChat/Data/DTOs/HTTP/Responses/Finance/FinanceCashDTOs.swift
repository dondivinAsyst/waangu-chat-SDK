//
//  FinanceCashDTOs.swift
//  FeatureChat
//
//  Phase 6 — espèces : dépôt chez un agent et jeton de retrait (§6).
//
//  Deux frontières portées par les champs eux-mêmes : `creditState` reste
//  `PENDING` après `physicalReceivedAt` (`CF_038`), et `consumedAt` n'est pas
//  une finalité financière.
//

import Foundation

/// `CashInOverlay` (§6, DTOs) — où en est un dépôt chez un agent.
///
/// `creditState` reste `PENDING` même après `physicalReceivedAt` : les deux
/// champs disent deux choses différentes, et les confondre est `CF_038`.
struct CashInOverlayDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let channel: String?
    let agentId: String?
    let agentVerified: Bool?
    let physicalReceivedAt: String?
    let financeRef: String?
    let creditState: String?
}

/// `POST /cash-out/token` (§6, DTOs) — le code en clair, **une seule fois**.
struct CashOutTokenDTO: Decodable, Equatable, Sendable {
    let token: String
    let expiresAt: String?
    let message: String?
}

/// `CashOutOverlay` (§6, DTOs) — où en est un retrait chez un agent.
///
/// `consumedAt` ≠ finalité financière, `remittedAt` n'écrit pas le ledger.
struct CashOutOverlayDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let channel: String?
    let agentId: String?
    let tokenHash: String?
    let tokenExpiresAt: String?
    let revoked: Bool?
    let consumedAt: String?
    let remittedAt: String?
    let incidentOpened: Bool?
}
