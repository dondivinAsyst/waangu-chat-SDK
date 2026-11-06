//
//  FinanceSendMoneyDTOs.swift
//  FeatureChat
//
//  Phase 3 — Send Money (INTEGRATION_CHAT_FINANCE.md §3).
//

import Foundation

// MARK: - §3.1 — POST /chat-core/financial/send-money/resolve-beneficiary

struct ResolvedBeneficiaryDTO: Decodable, Equatable, Sendable {
    /// Ce qui se reprend au prepare — **jamais** le nom seul.
    let beneficiaryToken: String
    let destinationType: String?
    let displayName: String?
    let counterpartyUserId: String?
    let eligible: Bool?
    let eligibilityReason: String?
    let country: String?
    let resolvedAt: String?
    let expiresAt: String?
}

// MARK: - §3.2 — POST /chat-core/financial/send-money/prepare

/// `PrepareSendMoneyResponse` — **vérité de l'écran de confirmation**.
struct PrepareSendMoneyResponseDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    /// `READY_FOR_CONFIRMATION` · `COMPLIANCE_HOLD` · …
    let status: String?
    let processRequired: Bool?
    let beneficiary: PreparedBeneficiaryDTO?
    let amountMinor: Int64?
    let currency: String?
    let quote: PreparedQuoteDTO?
    let objectVersion: String?
    let confirmation: PreparedConfirmationDTO?
    let executionPermitId: String?
    let nextSafeActions: [String]?
}

struct PreparedBeneficiaryDTO: Decodable, Equatable, Sendable {
    let beneficiaryToken: String?
    let displayName: String?
    /// Masqué (`USER_ID:…a12f`) : ne jamais le recalculer.
    let destination: String?
    let eligible: Bool?
    let expiresAt: String?
}

struct PreparedQuoteDTO: Decodable, Equatable, Sendable {
    let quoteId: String
    let currency: String?
    let principalMinor: Int64?
    let feeMinor: Int64?
    let totalMinor: Int64?
    let fxRate: Decimal?
    let expiresAt: String?
}

struct PreparedConfirmationDTO: Decodable, Equatable, Sendable {
    let confirmationId: String
    let fingerprint: String?
    let expiresAt: String?
}

// MARK: - §5 — POST /chat-core/financial/{operation}/prepare

/// `QuotedPrepareResponse` — bill / QR / invoice / top-up / cash / refund (§5).
///
/// Plat, contrairement à celui de Send Money : le devis n'est pas imbriqué.
struct QuotedPrepareResponseDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let status: String?
    let processRequired: Bool?
    let amountMinor: Int64?
    let currency: String?
    let quoteId: String?
    let feeMinor: Int64?
    let totalMinor: Int64?
    let fxRate: Decimal?
    let quoteExpiresAt: String?
    let objectVersion: String?
    let confirmation: PreparedConfirmationDTO?
    let merchantId: String?
    let storeId: String?
    let terminalId: String?
    let executionPermitId: String?
    let nextSafeActions: [String]?
}
