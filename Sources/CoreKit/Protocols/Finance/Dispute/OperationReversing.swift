//
//  OperationReversing.swift
//  CoreKit
//
//  Rembourser ou demander l'extourne d'une opération déjà faite — Phase 10.
//

import Foundation

/// `POST /refund` (un **devis**, puis le chemin de Send Money) et
/// `POST /reversal/request` (une **demande** : c'est Finance qui exécute).
///
/// Ni l'un ni l'autre n'est « un crédit magique » : le client ne fabrique jamais
/// un remboursement, il en prépare un que l'utilisateur confirme, ou il en
/// demande un que Finance exécutera.
public protocol OperationReversing: Sendable {

    /// `POST /refund` — prépare un remboursement de `reference`. Le devis rendu se
    /// confirme ensuite comme un envoi (`CF_047` si l'original n'est pas `COMPLETED`).
    func quoteRefund(of reference: FinancialReference, amount: Decimal, currency: String,
                     conversationID: String?,
                     idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `POST /reversal/request` — Chat journalise, Finance exécute.
    func requestReversal(of reference: FinancialReference, conversationID: String?,
                         reason: String) async -> Result<ReversalRequested, FinanceError>
}

public extension OperationReversing {
    func quoteRefund(of reference: FinancialReference, amount: Decimal, currency: String,
                     conversationID: String?,
                     idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func requestReversal(of reference: FinancialReference, conversationID: String?,
                         reason: String) async -> Result<ReversalRequested, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Ce que le serveur répond à une demande d'extourne : une **demande** enregistrée.
public struct ReversalRequested: Sendable, Hashable {
    public let originalIntentRef: String
    /// `REVERSAL_REQUESTED` — jamais « extourné » : Finance n'a pas encore exécuté.
    public let status: String
    public let message: String?

    public init(originalIntentRef: String, status: String, message: String? = nil) {
        self.originalIntentRef = originalIntentRef
        self.status = status
        self.message = message
    }
}

/// Le défaut : rien n'est offert.
public struct ClosedOperationReversing: OperationReversing {
    public init() {}
}
