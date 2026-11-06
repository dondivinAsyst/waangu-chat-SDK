//
//  PaymentLinkContract.swift
//  CoreKit
//
//  Liens de paiement — Bloc 6, chapitre 46.2.
//
//  **BACKEND CONTRACT REQUIRED** — résolution, consommation, révocation.
//

import Foundation

/// Liens de paiement partagés dans une conversation.
///
/// Un lien de paiement est **une invitation, pas une autorité**. Il ne porte ni
/// montant opposable, ni identité de marchand vérifiée : il porte un jeton que
/// seul le backend sait résoudre. Tout ce qu'un lien affirme de lui-même est
/// falsifiable, puisqu'un lien se recopie.
///
/// C'est précisément ce qui distingue ce contrat d'un simple `URL` : ici,
/// l'écran ne lit jamais le lien, il le fait résoudre.
public protocol PaymentLinkResolving: Sendable {

    /// Résout un lien reçu. **Seul point d'entrée.**
    ///
    /// Le `nonce` est produit par le client et lié à cette résolution : il
    /// empêche qu'une réponse capturée soit rejouée sur une autre tentative.
    func resolve(token: String, nonce: String) async -> Result<ResolvedPaymentLink, FinanceError>

    /// Crée un lien pour se faire payer.
    func create(
        _ request: PaymentLinkRequest,
        idempotency: IdempotencyContext
    ) async -> Result<IssuedPaymentLink, FinanceError>

    /// Révoque un lien émis. Irréversible.
    ///
    /// Sans révocation, un lien partagé dans un groupe reste payable jusqu'à son
    /// expiration — y compris après que son auteur a compris son erreur.
    func revoke(
        linkID: String,
        idempotency: IdempotencyContext
    ) async -> Result<Void, FinanceError>

    /// Liens émis par l'utilisateur, pour pouvoir les révoquer.
    func issuedLinks() async -> Result<[IssuedPaymentLink], FinanceError>
}

// MARK: - Lien résolu

/// Ce que le backend dit d'un lien, après résolution.
public struct ResolvedPaymentLink: Codable, Sendable, Hashable, Identifiable {

    public let id: String

    /// Ce que le lien permet de payer.
    public let target: PaymentLinkTarget

    /// Bénéficiaire **établi par le backend**, jamais lu dans le lien.
    public let payee: FinancialActor

    /// Montant, et son autorité. Un montant indicatif ne devient jamais ferme
    /// par le seul fait d'être affiché — c'est l'interdiction du §46.
    public let amount: PaymentLinkAmount

    public let usage: PaymentLinkUsage
    public let expiresAt: Date?

    /// `false` ⇒ affiché avec son motif, jamais payable.
    public let isPayable: Bool
    public let unavailableReasonKey: String?

    /// Le lien vient d'une source extérieure à l'application.
    ///
    /// Déclenche l'avertissement d'hameçonnage : un lien reçu par SMS ou collé
    /// depuis un site n'a pas la même présomption qu'un lien émis dans le fil.
    public let isExternalOrigin: Bool

    public init(id: String, target: PaymentLinkTarget, payee: FinancialActor,
                amount: PaymentLinkAmount, usage: PaymentLinkUsage,
                expiresAt: Date? = nil, isPayable: Bool,
                unavailableReasonKey: String? = nil, isExternalOrigin: Bool) {
        self.id = id
        self.target = target
        self.payee = payee
        self.amount = amount
        self.usage = usage
        self.expiresAt = expiresAt
        self.isPayable = isPayable
        self.unavailableReasonKey = unavailableReasonKey
        self.isExternalOrigin = isExternalOrigin
    }

    /// Payable **maintenant**.
    ///
    /// L'expiration est revérifiée localement en plus du drapeau serveur : un
    /// écran resté ouvert dix minutes afficherait sinon un lien périmé comme
    /// payable, et le refus n'arriverait qu'après la confirmation.
    public func isUsable(at now: Date = Date()) -> Bool {
        guard isPayable, payee.permissions.contains(.execute) else { return false }
        if let expiresAt, now >= expiresAt { return false }
        return true
    }
}

public enum PaymentLinkTarget: Sendable, Hashable, Codable {
    case invoice(id: String)
    case order(id: String)
    case merchantPayment(merchantID: String)
    case moneyRequest(id: String)
    case collection(id: String)
}

/// Un montant, et **qui l'a fixé**.
///
/// La distinction porte tout le §46 : « transformation d'un montant indicatif en
/// montant ferme » est interdite. Un type unique `Money?` la rendrait
/// impossible à exprimer, donc impossible à empêcher.
public enum PaymentLinkAmount: Sendable, Hashable, Codable {

    /// Montant arrêté par l'émetteur. Non modifiable.
    case fixed(Money)

    /// Le payeur saisit le montant, dans les bornes fournies.
    case open(minimum: Money?, maximum: Money?)

    /// Montant **indicatif** — un devis, un ordre de grandeur.
    ///
    /// Doit être présenté comme tel et **ne peut pas être payé directement** :
    /// il faut d'abord obtenir un montant ferme du backend.
    case indicative(Money)

    /// Seuls les deux premiers autorisent un paiement.
    public var isPayableAsIs: Bool {
        switch self {
        case .fixed, .open: return true
        case .indicative:   return false
        }
    }
}

public enum PaymentLinkUsage: String, Codable, Sendable, CaseIterable {
    /// Un seul paiement. La consommation est **serveur** : le client ne peut
    /// pas savoir si quelqu'un d'autre vient de l'utiliser.
    case singleUse = "SINGLE_USE"
    case reusable  = "REUSABLE"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Par défaut le plus restrictif : un lien de nature inconnue traité
        // comme réutilisable serait payable plusieurs fois.
        self = PaymentLinkUsage(rawValue: raw) ?? .singleUse
    }
}

// MARK: - Émission

public struct PaymentLinkRequest: Sendable, Hashable, Codable {
    public let target: PaymentLinkTarget
    public let amount: PaymentLinkAmount
    public let usage: PaymentLinkUsage
    public let expiresAfter: TimeInterval?
    public let labelKey: String?

    public init(target: PaymentLinkTarget, amount: PaymentLinkAmount,
                usage: PaymentLinkUsage, expiresAfter: TimeInterval? = nil,
                labelKey: String? = nil) {
        self.target = target
        self.amount = amount
        self.usage = usage
        self.expiresAfter = expiresAfter
        self.labelKey = labelKey
    }
}

public struct IssuedPaymentLink: Codable, Sendable, Hashable, Identifiable {

    public let id: String

    /// L'URL à partager. **Opaque** : la reconstruire ou la raccourcir invalide
    /// la signature que le backend y a placée.
    public let url: URL

    public let usage: PaymentLinkUsage
    public let amount: PaymentLinkAmount
    public let issuedAt: Date
    public let expiresAt: Date?
    public let state: PaymentLinkState

    /// Nombre de paiements reçus, **rendu par le backend**.
    public let paymentCount: Int

    public init(id: String, url: URL, usage: PaymentLinkUsage, amount: PaymentLinkAmount,
                issuedAt: Date, expiresAt: Date? = nil, state: PaymentLinkState,
                paymentCount: Int = 0) {
        self.id = id
        self.url = url
        self.usage = usage
        self.amount = amount
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.state = state
        self.paymentCount = paymentCount
    }

    /// Révocable tant qu'il pourrait encore servir. Révoquer un lien déjà
    /// consommé ou expiré n'a pas d'objet.
    public func isRevocable(at now: Date = Date()) -> Bool {
        guard state == .active else { return false }
        if let expiresAt, now >= expiresAt { return false }
        return true
    }
}

public enum PaymentLinkState: String, Codable, Sendable, CaseIterable {
    case active   = "ACTIVE"
    case consumed = "CONSUMED"
    case revoked  = "REVOKED"
    case expired  = "EXPIRED"
    case unknown  = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaymentLinkState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Défaut fermé

/// Ne résout, n'émet et ne révoque aucun lien.
///
/// Résoudre localement un lien « pour dépanner » reviendrait à faire confiance
/// à une chaîne de caractères que n'importe qui peut écrire.
public struct ClosedPaymentLinkResolver: PaymentLinkResolving {

    public init() {}

    public func resolve(token: String, nonce: String) async -> Result<ResolvedPaymentLink, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func create(_ request: PaymentLinkRequest,
                       idempotency: IdempotencyContext) async -> Result<IssuedPaymentLink, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func revoke(linkID: String,
                       idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func issuedLinks() async -> Result<[IssuedPaymentLink], FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
