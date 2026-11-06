//
//  PaymentConfirmationGuardProtocol.swift
//  CoreKit
//
//  Protocol abstraction for PaymentConfirmationGuard
//
//  RÈGLE : le client ne confirme aucun paiement. Il vérifie que ce que le backend
//  lui présente comme confirmé l'est réellement, et refuse d'afficher le contraire.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.5.

import Foundation

// MARK: - Résultat historique

/// Validation result for payment confirmation
public enum PaymentConfirmationValidationResult: Sendable, Equatable {
    case valid
    case invalid(reason: String)
}

// MARK: - Décision motivée

/// Verdict du garde sur une confirmation présentée par le backend.
///
/// Trois issues et non deux. Le troisième cas existe parce que « je ne peux pas
/// vérifier » n'est pas « c'est faux » : traiter l'invérifiable comme un refus
/// masquerait un paiement réellement abouti, et le traiter comme une acceptation
/// afficherait un paiement qui ne l'est peut-être pas.
public enum PaymentConfirmationDecision: Sendable, Equatable {

    /// Vérifié. La confirmation peut être affichée comme telle.
    case accepted

    /// Contredit par les éléments présentés. Ne jamais afficher comme confirmé.
    case rejected(PaymentConfirmationRejection)

    /// Non vérifiable par ce client. L'objet doit être présenté en `unknown` et
    /// réconcilié — jamais rendu comme confirmé, jamais rendu comme échoué.
    case undetermined(PaymentConfirmationRejection)
}

/// Motif d'un refus ou d'une indétermination.
///
/// Enum et non `String` : le motif est consommé par du code (choix de l'affichage,
/// alerte d'observabilité) autant que lu par un humain. Une chaîne libre se compare
/// mal et se traduit encore moins bien.
public enum PaymentConfirmationRejection: Sendable, Equatable {

    /// Aucune signature backend n'accompagne la confirmation.
    case missingSignature

    /// Signature présente mais non vérifiée cryptographiquement.
    case unverifiedSignature

    /// Preuve de rail absente : le rail externe n'a rien confirmé.
    case missingRailProof

    /// Montant nul ou négatif.
    case nonPositiveAmount

    /// La confirmation porte une révision antérieure ou égale à celle déjà connue.
    case staleVersion(incoming: Int, current: Int)

    /// Le statut présenté n'est pas un état final de succès.
    case statusNotFinal(PaymentStatus)

    /// Le contrat backend de signature n'est pas encore livré : ce client ne peut
    /// structurellement pas vérifier. Voir contrat #1 du §15.
    case backendContractPending

    /// Message affichable. Volontairement vague côté utilisateur : le détail
    /// renseignerait un attaquant sur ce qui a été contrôlé.
    public var displayReason: String {
        switch self {
        case .staleVersion:
            return "Information périmée"
        case .nonPositiveAmount:
            return "Montant invalide"
        default:
            return "Confirmation non vérifiable"
        }
    }

    /// Détail réservé aux logs et à l'observabilité.
    public var technicalDetail: String {
        switch self {
        case .missingSignature:      return "missing_signature"
        case .unverifiedSignature:   return "unverified_signature"
        case .missingRailProof:      return "missing_rail_proof"
        case .nonPositiveAmount:     return "non_positive_amount"
        case .staleVersion(let i, let c): return "stale_version(in:\(i),cur:\(c))"
        case .statusNotFinal(let s): return "status_not_final(\(s.rawValue))"
        case .backendContractPending: return "backend_contract_pending"
        }
    }
}

// MARK: - PaymentConfirmation

/// Ce qui est présenté au garde pour vérification.
///
/// Porte la `FinancialReference` — donc la révision — parce qu'une confirmation
/// valablement signée mais périmée reste irrecevable : elle ferait régresser
/// l'affichage vers un état antérieur.
public struct PaymentConfirmation: Sendable, Equatable {

    public let reference: FinancialReference
    public let amount: Decimal
    public let currency: String
    public let status: PaymentStatus

    /// Signature émise par le backend sur le contenu canonique de l'objet.
    public let backendSignature: String

    /// Preuve remise par le rail externe. `nil` si le rail n'en fournit pas encore.
    public let railProof: RailProof?

    /// Révision déjà connue localement, si l'objet est déjà en cache.
    public let currentKnownVersion: Int?

    /// Clé d'idempotence de l'opération — couverte par la signature backend.
    ///
    /// Présente ici parce qu'elle fait partie du contenu signé : sans elle, le
    /// garde ne peut pas reconstruire ce que le backend a signé, donc ne peut
    /// rien vérifier.
    public let idempotencyKey: String

    public init(
        reference: FinancialReference,
        amount: Decimal,
        currency: String,
        status: PaymentStatus,
        backendSignature: String,
        idempotencyKey: String,
        railProof: RailProof? = nil,
        currentKnownVersion: Int? = nil
    ) {
        self.reference = reference
        self.amount = amount
        self.currency = currency
        self.status = status
        self.backendSignature = backendSignature
        self.idempotencyKey = idempotencyKey
        self.railProof = railProof
        self.currentKnownVersion = currentKnownVersion
    }
}

// MARK: - Contrat

public protocol PaymentConfirmationGuardProtocol: Sendable {

    /// Vérifie une confirmation présentée par le backend et rend une décision motivée.
    ///
    /// Seul point d'entrée du Bloc 1. Une implémentation ne peut plus s'en acquitter
    /// par un contrôle de longueur de chaîne : elle doit se prononcer sur la
    /// signature, la preuve de rail et la fraîcheur de la révision, et distinguer
    /// le refus de l'indétermination.
    func decide(on confirmation: PaymentConfirmation) async -> PaymentConfirmationDecision

    /// Validate payment confirmation from server
    ///
    /// - Warning: Contrat historique, conservé pour les appelants antérieurs au
    ///   Bloc 1. Ne porte ni révision ni preuve de rail, donc ne peut pas détecter
    ///   un rejeu — utiliser `decide(on:)`.
    @available(*, deprecated, message: "Utiliser decide(on:) — ce contrat ne détecte ni rejeu ni régression de version.")
    func validate(
        transactionId: String,
        amount: Decimal,
        signature: String
    ) async -> PaymentConfirmationValidationResult
}

// MARK: - Pont vers le contrat historique

public extension PaymentConfirmationGuardProtocol {

    /// Implémentation par défaut, pour qu'un conformeur écrit après le Bloc 1
    /// n'ait pas à porter le contrat historique.
    ///
    /// `undetermined` y est rendu comme `invalid` faute de troisième cas dans
    /// l'ancien type — raison de plus pour ne plus l'utiliser : il ne sait pas
    /// exprimer la différence entre « c'est faux » et « je ne sais pas ».
    @available(*, deprecated, message: "Utiliser decide(on:).")
    func validate(
        transactionId: String,
        amount: Decimal,
        signature: String
    ) async -> PaymentConfirmationValidationResult {
        let confirmation = PaymentConfirmation(
            reference: FinancialReference(
                type: .payment,
                id: transactionId,
                version: 0,
                correlationID: CorrelationId()
            ),
            amount: amount,
            currency: "",
            status: .unknown,
            backendSignature: signature,
            idempotencyKey: ""
        )
        switch await decide(on: confirmation) {
        case .accepted:
            return .valid
        case .rejected(let reason), .undetermined(let reason):
            return .invalid(reason: reason.displayReason)
        }
    }
}
