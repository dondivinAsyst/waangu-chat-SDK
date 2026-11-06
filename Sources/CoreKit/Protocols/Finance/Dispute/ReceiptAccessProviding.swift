//
//  ReceiptAccessProviding.swift
//  CoreKit
//
//  Accès aux reçus — Bloc 3, chapitre 24.
//
//  **BACKEND CONTRACT REQUIRED** — `GET /v1/receipts/{receiptId}`.
//

import Foundation

/// Donne accès aux reçus émis par le backend.
///
/// **Aucune génération côté client.** Fabriquer un PDF localement produirait un
/// document qui ressemble à un reçu officiel sans en être un — et qui
/// circulerait comme tel, chez un employeur, une administration, un tribunal.
public protocol ReceiptAccessProviding: Sendable {

    /// URL signée et expirante vers le reçu.
    func receipt(
        for reference: FinancialReference,
        variant: ReceiptVariant
    ) async -> Result<SignedReceipt, FinanceError>

    /// `POST /receipt/share` — publie la **carte du reçu** dans la conversation,
    /// après `COMPLETED`. Ce n'est pas l'URL signée : c'est ce que les autres
    /// membres voient.
    func postInConversation(_ reference: FinancialReference,
                            conversationID: String) async -> Result<Void, FinanceError>

    /// `POST /receipts/verify` — le document rendu est-il celui que Finance a signé ?
    /// Un hash qui ne correspond pas est `CF_045`.
    func verify(receiptID: String, documentBody: String) async -> Result<Void, FinanceError>
}

public extension ReceiptAccessProviding {
    func postInConversation(_ reference: FinancialReference,
                            conversationID: String) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func verify(receiptID: String, documentBody: String) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

// MARK: - Variantes

public enum ReceiptVariant: String, Codable, Sendable, CaseIterable {

    /// Émis avant finalité. **Doit être visuellement distinct du final** : un
    /// provisoire présenté comme définitif est un faux justificatif.
    case provisional = "PROVISIONAL"

    case final = "FINAL"

    /// Version expurgée, destinée au partage hors du cercle de l'opération.
    case redacted = "REDACTED"
}

// MARK: - Reçu signé

public struct SignedReceipt: Sendable, Hashable, Codable {

    public let receiptID: String
    public let variant: ReceiptVariant

    /// URL temporaire. Ne jamais mettre en cache au-delà de son échéance : une
    /// URL de reçu recopiée reste ouvrable par quiconque la détient.
    public let url: URL
    public let expiresAt: Date

    /// Empreinte publiée par le backend, pour vérification d'authenticité.
    public let documentHash: String

    /// Révision du reçu. Un reçu régénéré après correction porte une révision
    /// supérieure — deux versions d'un même reçu doivent être distinguables.
    public let version: Int

    /// `true` si ce reçu peut être partagé hors de l'application.
    /// Décidé par le backend : la politique de partage est réglementaire.
    public let isShareable: Bool

    public init(
        receiptID: String, variant: ReceiptVariant, url: URL,
        expiresAt: Date, documentHash: String, version: Int, isShareable: Bool
    ) {
        self.receiptID = receiptID
        self.variant = variant
        self.url = url
        self.expiresAt = expiresAt
        self.documentHash = documentHash
        self.version = version
        self.isShareable = isShareable
    }
}

public extension SignedReceipt {

    func isExpired(asOf now: Date = Date()) -> Bool { now >= expiresAt }

    /// `true` si le reçu peut être ouvert maintenant.
    func isOpenable(asOf now: Date = Date()) -> Bool { !isExpired(asOf: now) }

    /// `true` si le partage doit être proposé.
    ///
    /// Les deux conditions comptent : un reçu provisoire partageable reste un
    /// document qui dit « payé » avant que ce soit vrai.
    func allowsSharing(asOf now: Date = Date()) -> Bool {
        isShareable && variant != .provisional && !isExpired(asOf: now)
    }
}
