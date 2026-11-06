//
//  FinanceRequestMoneyDTOs.swift
//  FeatureChat
//
//  Phase 4 — Request Money et partage (INTEGRATION_CHAT_FINANCE.md §4).
//
//  Un partage est une demande à plusieurs parts nommées : `POST /split-bill`
//  rend le **même** `RequestView`, avec `kind: "SPLIT_BILL"`.
//

import Foundation

/// `RequestView` — réponse de `POST /request-money` et de `GET /request-money/{requestRef}`.
struct RequestViewDTO: Decodable, Equatable, Sendable {
    let requestRef: String
    let conversationId: String?
    let requesterUserId: String?
    /// `OPEN` · `EXPIRED` · `CANCELLED` · `COMPLETED`.
    let status: String?
    let processRequired: Bool?
    /// `FIXED` · `FREE`.
    let amountMode: String?
    let currency: String?
    let amountMinor: Int64?
    let expiresAt: String?
    let parties: [RequestPartyDTO]?
    let note: String?
    let kind: String?
    let nextSafeActions: [String]?
}

struct RequestPartyDTO: Decodable, Equatable, Sendable {
    /// Identifiant **Chat** — jamais un identifiant de partie Finance à la place.
    let chatUserId: String
    let requestedMinor: Int64?
    let paidMinor: Int64?
    let remainingMinor: Int64?
    let currency: String?
    let status: String?
}

/// `PaymentLink` — Phase 4. `executable` est **toujours `false`**.
struct PaymentLinkDTO: Decodable, Equatable, Sendable {
    let token: String
    let nonce: String
    let requestRef: String
    let conversationId: String?
    let expiresAt: String?
    let executable: Bool?
    let consumedAt: String?
}
