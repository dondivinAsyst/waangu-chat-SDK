//
//  ConfirmationSnapshot.swift
//  CoreKit
//
//  Ce que l'utilisateur avait sous les yeux quand il a décidé — Bloc 2 §13.4.
//

import Foundation
import CryptoKit

/// L'état exact des conditions au moment de l'accord de l'utilisateur.
///
/// Comparé à un rafraîchissement fait juste avant l'exécution. Toute divergence
/// sur un champ décisionnel annule la confirmation et impose un nouvel accord.
///
/// **Il n'existe pas de divergence « mineure ».** L'utilisateur n'a pas consenti
/// à « environ ce montant vers à peu près cette personne » : il a consenti à des
/// valeurs précises. Les scénarios 13 à 16 du Bloc 2 — bénéficiaire, frais, FX et
/// conformité modifiés entre l'aperçu et la confirmation — sont exactement ce que
/// ce type rend détectable.
public struct ConfirmationSnapshot: Sendable, Equatable, Codable {

    public let reference: FinancialReference

    public let amount: Decimal
    public let currency: String
    public let feeAmount: Decimal?
    public let feeCurrency: String?
    public let exchangeRate: Decimal?

    public let recipientID: String
    public let recipientVerification: VerificationStatus

    public let complianceState: ComplianceState

    /// Instant de capture, **horloge serveur**.
    ///
    /// Une horloge client permettrait de rajeunir un aperçu périmé en changeant
    /// l'heure de l'appareil.
    public let capturedAt: Date

    public init(
        reference: FinancialReference,
        amount: Decimal,
        currency: String,
        feeAmount: Decimal? = nil,
        feeCurrency: String? = nil,
        exchangeRate: Decimal? = nil,
        recipientID: String,
        recipientVerification: VerificationStatus,
        complianceState: ComplianceState,
        capturedAt: Date
    ) {
        self.reference = reference
        self.amount = amount
        self.currency = currency
        self.feeAmount = feeAmount
        self.feeCurrency = feeCurrency
        self.exchangeRate = exchangeRate
        self.recipientID = recipientID
        self.recipientVerification = recipientVerification
        self.complianceState = complianceState
        self.capturedAt = capturedAt
    }
}

// MARK: - Divergences

/// Un champ dont la modification invalide l'accord de l'utilisateur.
public enum DecisionField: String, Sendable, Equatable, CaseIterable {
    case amount
    case currency
    case fee
    case exchangeRate
    case recipient
    case recipientVerification
    case compliance
    case objectIdentity
}

public extension ConfirmationSnapshot {

    /// Ce qui a changé entre cet aperçu et un état rafraîchi.
    ///
    /// La **version** de l'objet est délibérément absente de la comparaison : une
    /// révision plus récente n'est pas en soi une divergence décisionnelle, le
    /// backend en produit pour des raisons qui ne changent rien pour
    /// l'utilisateur. C'est le contenu qui compte, pas le compteur.
    ///
    /// L'**identité** de l'objet, elle, est comparée : un rafraîchissement qui
    /// porte sur un autre objet n'est pas une divergence, c'est un défaut de
    /// dispatch — et l'exécuter serait payer autre chose que ce qui a été montré.
    func divergences(from fresh: ConfirmationSnapshot) -> [DecisionField] {
        var fields: [DecisionField] = []

        if !reference.identifies(fresh.reference) { fields.append(.objectIdentity) }
        if amount != fresh.amount                 { fields.append(.amount) }
        if currency != fresh.currency             { fields.append(.currency) }
        if feeAmount != fresh.feeAmount || feeCurrency != fresh.feeCurrency {
            fields.append(.fee)
        }
        if exchangeRate != fresh.exchangeRate     { fields.append(.exchangeRate) }
        if recipientID != fresh.recipientID       { fields.append(.recipient) }
        if recipientVerification != fresh.recipientVerification {
            fields.append(.recipientVerification)
        }
        if complianceState != fresh.complianceState { fields.append(.compliance) }

        return fields
    }

    /// `true` si l'exécution peut se poursuivre sans nouvel accord.
    func matches(_ fresh: ConfirmationSnapshot) -> Bool {
        divergences(from: fresh).isEmpty
    }
}

// MARK: - Empreinte

public extension ConfirmationSnapshot {

    /// Empreinte des champs décisionnels, à lier au permis d'exécution.
    ///
    /// **BACKEND CONTRACT REQUIRED** — la forme canonique doit être identique des
    /// deux côtés, sinon le backend rejettera un permis pourtant légitime. Elle
    /// est volontairement simple et ordonnée : champs décisionnels seulement,
    /// séparateur fixe, aucune dépendance à l'ordre de sérialisation JSON, qui
    /// n'est pas garanti.
    ///
    /// `capturedAt` en est exclu : deux captures identiques à des instants
    /// différents décrivent les mêmes conditions. Inclure l'horodatage rendrait
    /// chaque empreinte unique et le contrôle inopérant.
    var decisionHash: String {
        let canonical = [
            reference.identityKey,
            "\(amount)",
            currency,
            feeAmount.map { "\($0)" } ?? "-",
            feeCurrency ?? "-",
            exchangeRate.map { "\($0)" } ?? "-",
            recipientID,
            recipientVerification.rawValue,
            complianceState.rawValue
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ComplianceState

/// État du contrôle de conformité, **séparé du cycle de vie du rail**.
///
/// Bloc 2 §9.2. Aujourd'hui `complianceHold`, `amlReview`, `denied` et
/// `restricted` vivent dans `PaymentStatus`, ce qui rend impossible de
/// représenter un paiement en cours de traitement **et** bloqué par un contrôle
/// AML — le modèle force alors à mentir sur l'un des deux.
public enum ComplianceState: String, Codable, Sendable, Equatable, CaseIterable {

    case notApplicable    = "NOT_APPLICABLE"
    case pending          = "PENDING"
    case approvalRequired = "APPROVAL_REQUIRED"
    case approved         = "APPROVED"
    case denied           = "DENIED"
    case blocked          = "BLOCKED"

    /// Un état inconnu n'est jamais `approved`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ComplianceState(rawValue: raw) ?? .pending
    }

    /// `true` si l'exécution peut se poursuivre.
    /// Fermé par défaut : seul `approved` et `notApplicable` laissent passer.
    public var allowsExecution: Bool {
        self == .approved || self == .notApplicable
    }
}
