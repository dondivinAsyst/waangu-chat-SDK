//
//  FinancialSignatureVerifying.swift
//  CoreKit
//
//  Vérification d'authenticité d'un objet financier.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.5 et §15 (contrat backend #1).

import Foundation

/// Vérifie qu'un objet financier vient bien du backend.
///
/// Contrat séparé du garde de confirmation à dessein : le garde décide *quoi
/// afficher*, ce vérificateur répond *est-ce authentique*. Les mêler produit
/// exactement le défaut d'origine — un garde qui « valide » en comptant des
/// caractères parce que la vraie vérification n'avait nulle part où vivre.
///
/// L'implémentation ne détient jamais de secret partagé en dur. La clé de
/// vérification vient du trousseau, alimentée par l'IdentityGateway.
public protocol FinancialSignatureVerifying: Sendable {

    /// Vérifie la signature d'un contenu canonique.
    ///
    /// - Returns: le verdict, qui distingue « invalide » de « invérifiable ».
    func verify(
        signature: String,
        over payload: FinancialSignaturePayload
    ) async -> FinancialSignatureVerdict

    /// `true` si ce vérificateur dispose d'une clé utilisable.
    ///
    /// Permet à l'appelant de choisir sa présentation en amont plutôt que de
    /// découvrir l'indisponibilité au moment d'afficher une carte.
    func isOperational() async -> Bool
}

// MARK: - Verdict

public enum FinancialSignatureVerdict: Sendable, Equatable {

    /// Signature authentique.
    case authentic

    /// Signature présente et vérifiable, mais fausse. Contenu à rejeter.
    case forged

    /// Impossible de se prononcer — aucune clé configurée, algorithme inconnu.
    ///
    /// **N'est pas un succès.** L'appelant doit présenter l'objet en `unknown`
    /// et réconcilier. Le distinguer de `forged` évite d'accuser le backend de
    /// falsification quand le seul problème est un client non configuré.
    case unverifiable(reason: String)
}

// MARK: - Contenu signé

/// Les champs couverts par la signature backend.
///
/// **BACKEND CONTRACT REQUIRED** — contrat #1. La liste des champs et leur ordre
/// doivent correspondre exactement à ce que signe le backend. Toute divergence
/// rend chaque signature invalide, ce qui est le mode d'échec sûr : rien ne
/// s'affiche comme confirmé.
public struct FinancialSignaturePayload: Sendable, Equatable {

    public let objectType: FinancialObjectType
    public let objectID: String
    public let version: Int
    public let amount: Decimal
    public let currency: String
    public let status: PaymentStatus
    public let idempotencyKey: String

    public init(
        objectType: FinancialObjectType,
        objectID: String,
        version: Int,
        amount: Decimal,
        currency: String,
        status: PaymentStatus,
        idempotencyKey: String
    ) {
        self.objectType = objectType
        self.objectID = objectID
        self.version = version
        self.amount = amount
        self.currency = currency
        self.status = status
        self.idempotencyKey = idempotencyKey
    }

    /// Sérialisation canonique soumise à la signature.
    ///
    /// Ordre fixe et séparateur non ambigu. Le montant passe par
    /// `NSDecimalNumber.description`, stable et indépendant de la locale — un
    /// formatage localisé produirait « 1,50 » ici et « 1.50 » côté serveur, donc
    /// deux signatures différentes pour le même montant.
    ///
    /// Le séparateur `|` impose que les champs n'en contiennent pas ; les
    /// identifiants backend et les codes devise n'en contiennent pas.
    public var canonicalForm: String {
        [
            objectType.rawValue,
            objectID,
            String(version),
            NSDecimalNumber(decimal: amount).description,
            currency,
            status.rawValue,
            idempotencyKey
        ].joined(separator: "|")
    }

    public var canonicalData: Data { Data(canonicalForm.utf8) }
}

// MARK: - Construction depuis une enveloppe

public extension FinancialSignaturePayload {

    /// Reconstruit le contenu signé à partir d'une enveloppe reçue.
    ///
    /// La révision vient de la `FinancialReference` et non de l'enveloppe :
    /// `PaymentEnvelope.version` est une version de *schéma* (`String`), pas une
    /// révision d'objet. Les confondre signerait un contenu sans lien avec
    /// l'ordre des événements, et laisserait passer un rejeu.
    init(envelope: PaymentEnvelope, reference: FinancialReference) {
        self.init(
            objectType: reference.type,
            objectID: reference.id,
            version: reference.version,
            amount: envelope.amount,
            currency: envelope.currency,
            status: envelope.status,
            idempotencyKey: envelope.idempotencyKey
        )
    }

    /// Contenu signé d'une confirmation présentée au garde.
    init(confirmation: PaymentConfirmation, idempotencyKey: String) {
        self.init(
            objectType: confirmation.reference.type,
            objectID: confirmation.reference.id,
            version: confirmation.reference.version,
            amount: confirmation.amount,
            currency: confirmation.currency,
            status: confirmation.status,
            idempotencyKey: idempotencyKey
        )
    }
}
