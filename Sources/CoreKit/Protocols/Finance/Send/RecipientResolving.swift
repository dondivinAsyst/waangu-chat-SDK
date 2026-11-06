//
//  RecipientResolving.swift
//  CoreKit
//
//  Résolution du bénéficiaire — Bloc 2, chapitre 10 §10.3.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /recipient/resolve`.
//  Voir BLOC2-MODELE-CONVERSATIONNEL-FINANCIER.md PARTIE 12.
//

import Foundation

/// Transforme une saisie utilisateur en bénéficiaire établi par le backend.
///
/// **`téléphone ≠ portefeuille`.** C'est la règle que ce contrat rend structurelle
/// plutôt que déclarative : aucune méthode n'accepte un numéro et ne rend un
/// identifiant de portefeuille. La seule sortie possible est un
/// `ResolvedRecipient`, qui porte obligatoirement un statut de vérification —
/// l'appelant ne peut donc pas obtenir un identifiant sans obtenir aussi ce qu'on
/// en sait.
///
/// Un numéro de téléphone est une saisie, pas une identité financière : il se
/// recycle, se porte d'un opérateur à l'autre, et se tape de travers.
public protocol RecipientResolving: Sendable {

    /// Résout une saisie en bénéficiaire.
    ///
    /// - Returns: le bénéficiaire **et** ce que le backend en sait, ou l'échec
    ///   typé. Ne rend jamais un identifiant nu : un appelant serait alors libre
    ///   d'ignorer le statut de vérification, ce qui est exactement le chemin de
    ///   la fraude au bénéficiaire.
    func resolve(_ input: RecipientInput) async -> Result<ResolvedRecipient, FinanceError>

    /// Résout en signalant le nom sous lequel l'émetteur connaît ce bénéficiaire.
    ///
    /// - Parameter localName: le nom du répertoire de l'émetteur — le contact,
    ///   le titre de la conversation. **Indicatif, jamais affiché tel quel.**
    ///
    /// Ce que le backend en fait : il le compare au titulaire réel du compte et
    /// signale l'écart. Un numéro qui change de mains ne change pas de nom dans
    /// le répertoire de l'émetteur, et c'est exactement ce qui rend la fraude au
    /// bénéficiaire invisible ; seul celui qui connaît les deux noms peut la
    /// voir.
    ///
    /// Un conformeur qui n'a pas cet usage l'ignore : l'implémentation par
    /// défaut retombe sur ``resolve(_:)``.
    func resolve(
        _ input: RecipientInput,
        knownAs localName: String?
    ) async -> Result<ResolvedRecipient, FinanceError>
}

public extension RecipientResolving {

    /// Ignore l'indication et résout normalement.
    ///
    /// Le nom local n'est **pas** substitué au nom rendu : afficher le nom du
    /// répertoire à la place de celui du titulaire masquerait précisément
    /// l'écart que ce paramètre sert à révéler.
    func resolve(
        _ input: RecipientInput,
        knownAs localName: String?
    ) async -> Result<ResolvedRecipient, FinanceError> {
        await resolve(input)
    }
}

// MARK: - Entrée

/// Ce que l'utilisateur a fourni, sans interprétation.
///
/// Le type conserve la **nature** de la saisie jusqu'au backend. Aplatir en
/// `String` obligerait quelqu'un, quelque part, à deviner si « 25761… » est un
/// numéro ou un code marchand — et ce quelqu'un serait le client.
public enum RecipientInput: Sendable, Hashable, Codable {

    case phoneNumber(String)
    case walletHandle(String)
    case merchantCode(String)

    /// Charge d'un QR déjà scanné.
    ///
    /// Passe par le backend comme le reste : un QR est falsifiable, et le
    /// vérifier localement reviendrait à faire confiance à ce qu'on veut vérifier.
    case qrPayload(String)

    // ── Bloc 5, chapitre 35 ──────────────────────────────────

    /// Compte bancaire. Les champs varient par pays — IBAN en zone SEPA,
    /// numéro + institution + transit au Canada, numéro + banque ailleurs.
    /// Le backend seul sait lesquels s'appliquent au corridor demandé.
    case bankAccount(BankAccountInput)

    /// Compte Mobile Money chez un opérateur nommé.
    ///
    /// L'opérateur est **fourni**, jamais déduit du préfixe : la portabilité des
    /// numéros rend toute déduction locale fausse tôt ou tard, et créditer le
    /// mauvais opérateur est une perte sèche.
    case mobileMoney(operatorID: String, msisdn: String)

    /// Retrait en espèces chez un agent, identifié par son code.
    case cashPickup(agentNetworkID: String)
}

/// Coordonnées bancaires, telles que saisies.
///
/// Aucun champ n'est validé localement au-delà de la forme : ce qui constitue un
/// numéro valide dépend de l'institution et du pays, et un motif client trop
/// strict refuserait un compte pourtant réel.
public struct BankAccountInput: Sendable, Hashable, Codable {
    public let countryCode: String
    /// IBAN, ou numéro de compte local selon le corridor.
    public let accountNumber: String
    /// BIC/SWIFT, code institution, ou identifiant local.
    public let institutionCode: String?
    /// Transit / agence, requis dans certains pays.
    public let branchCode: String?
    public let accountHolderName: String

    public init(countryCode: String, accountNumber: String,
                institutionCode: String? = nil, branchCode: String? = nil,
                accountHolderName: String) {
        self.countryCode = countryCode
        self.accountNumber = accountNumber
        self.institutionCode = institutionCode
        self.branchCode = branchCode
        self.accountHolderName = accountHolderName
    }
}

// MARK: - Sortie

/// Un bénéficiaire établi, et ce que le backend en dit.
public struct ResolvedRecipient: Sendable, Hashable, Codable {

    /// Identifiant opaque, seul admis par `CreatePaymentIntentRequest.recipientID`.
    public let recipientID: String

    public let actor: FinancialActor

    /// `true` si l'émetteur n'a jamais payé ce bénéficiaire.
    ///
    /// Déclenche l'avertissement d'interface. Établi par le backend, qui seul
    /// connaît l'historique complet — le client n'a que ce qu'il a en cache.
    public let isNewToSender: Bool

    public let riskSignal: RecipientRiskSignal

    /// Fin du délai de réflexion imposé avant un premier envoi.
    /// `nil` si aucun délai ne s'applique. JURISDICTION CONTROLLED.
    public let coolingOffUntil: Date?

    /// Relation déclarée à ce bénéficiaire — exigée en remittance par la
    /// plupart des régulateurs. **Déclarée par l'utilisateur, vérifiée nulle
    /// part côté client.**
    public let declaredRelationship: String?

    /// Objet déclaré du transfert.
    public let declaredPurpose: String?

    /// Instant de résolution, **horloge serveur**.
    ///
    /// Sert au chapitre 13 : entre l'aperçu et la confirmation, un bénéficiaire
    /// résolu il y a trop longtemps doit être re-résolu.
    public let resolvedAt: Date

    public init(
        recipientID: String,
        actor: FinancialActor,
        isNewToSender: Bool = false,
        riskSignal: RecipientRiskSignal = .none,
        coolingOffUntil: Date? = nil,
        declaredRelationship: String? = nil,
        declaredPurpose: String? = nil,
        resolvedAt: Date
    ) {
        self.recipientID = recipientID
        self.actor = actor
        self.isNewToSender = isNewToSender
        self.riskSignal = riskSignal
        self.coolingOffUntil = coolingOffUntil
        self.declaredRelationship = declaredRelationship
        self.declaredPurpose = declaredPurpose
        self.resolvedAt = resolvedAt
    }
}

// MARK: - Signal de risque

/// Ce que le contrôle de risque backend a relevé sur ce bénéficiaire.
public enum RecipientRiskSignal: String, Codable, Sendable, CaseIterable {

    case none          = "NONE"
    case newRecipient  = "NEW_RECIPIENT"
    case unusualAmount = "UNUSUAL_AMOUNT"
    case velocityFlag  = "VELOCITY_FLAG"

    /// Bénéficiaire refusé. Aucune opération ne doit être proposée.
    case blocked       = "BLOCKED"

    /// Un signal inconnu de ce client est traité comme **présent**, pas comme absent.
    ///
    /// L'inverse de `PaymentStatus`, et pour la même raison de fond : ici le
    /// défaut sûr est de signaler. Un signal de risque qu'on ne sait pas
    /// interpréter ne doit pas disparaître silencieusement de l'interface.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RecipientRiskSignal(rawValue: raw) ?? .velocityFlag
    }
}

// MARK: - Confort

public extension ResolvedRecipient {

    /// `true` si l'utilisateur doit voir un avertissement avant de confirmer.
    var warrantsConfirmationWarning: Bool {
        isNewToSender
            || actor.verification.warrantsWarning
            || riskSignal != .none
    }

    /// `true` si le délai de réflexion court encore.
    func isInCoolingOff(asOf now: Date = Date()) -> Bool {
        guard let coolingOffUntil else { return false }
        return coolingOffUntil > now
    }

    /// `true` si une opération peut être proposée vers ce bénéficiaire.
    ///
    /// Fermé par défaut : bloqué ou en délai de réflexion, rien n'est proposable.
    func allowsPayment(asOf now: Date = Date()) -> Bool {
        riskSignal != .blocked
            && actor.verification != .revoked
            && !isInCoolingOff(asOf: now)
    }
}
