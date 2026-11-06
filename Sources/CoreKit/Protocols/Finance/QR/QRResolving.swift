//
//  QRResolving.swift
//  CoreKit
//
//  Résolution d'un QR financier — Bloc 3, chapitre 22.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/qr/resolve`.
//

import Foundation

/// Résout une charge de QR auprès du backend.
///
/// > **Aucun QR n'est exécutable sans résolution serveur.**
///
/// Cette règle est la raison d'être du protocole. Un QR est un support
/// falsifiable : n'importe qui peut en imprimer un et le coller sur celui d'un
/// marchand. Vérifier sa signature localement reviendrait à faire confiance à ce
/// qu'on cherche justement à vérifier — la clé publique embarquée serait
/// remplaçable au même titre que le reste.
///
/// Le client ne fait donc que trois choses : décoder, classer grossièrement,
/// et envoyer. Tout le reste — identité, montant, expiration, actions
/// autorisées — vient de la réponse.
public protocol QRResolving: Sendable {

    /// - Parameter payload: la charge brute décodée, **jamais interprétée**.
    /// - Parameter nonce: valeur à usage unique produite par le client pour
    ///   cette tentative. Le backend la rejette si elle a déjà servi : c'est ce
    ///   qui transforme un rejeu en refus explicite plutôt qu'en second débit.
    func resolve(
        payload: String,
        nonce: String
    ) async -> Result<ResolvedQR, FinanceError>

    /// `POST /qr/prepare` (§5.2) — **un devis** pour payer ce code, la charge
    /// envoyée telle quelle. Le montant et le marchand sont ceux du serveur.
    /// L'execute (`/qr/execute`) suit après confirmation explicite.
    func quotePayment(payload: String, conversationID: String?,
                      idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `true` si cette implémentation demande ce devis au serveur.
    var providesQuotes: Bool { get }
}

public extension QRResolving {
    /// Par défaut : pas de devis — seul un client branché sur `/qr/prepare` en rend un.
    func quotePayment(payload: String, conversationID: String?,
                      idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    var providesQuotes: Bool { false }
}

// MARK: - Résultat

/// Ce que le backend dit d'un QR.
public struct ResolvedQR: Sendable, Hashable, Codable {

    public let reference: FinancialReference
    public let kind: QRKind

    /// Contrepartie établie par le backend.
    public let counterparty: FinancialActor

    /// Montant imposé par le QR. `nil` ⇒ QR statique, le payeur saisit.
    public let amount: Decimal?
    public let currency: String?

    /// Actions permises, **rendues par le backend**.
    ///
    /// Jamais dérivées du type de QR côté client : les dériver reviendrait à
    /// décider ce qui est permis, donc à réintroduire une décision
    /// d'autorisation dans le Chat.
    public let allowedActions: Set<FinancialPermission>

    public let expiresAt: Date?

    /// `true` si la charge provient d'une source externe à l'application —
    /// photo de la galerie, lien reçu. Voir `requiresQuarantineWarning`.
    public let isExternalOrigin: Bool

    /// Identité de messagerie de la contrepartie, **quand le backend la rend**.
    ///
    /// `counterparty` est un acteur financier : un identifiant opaque et un nom.
    /// Il suffit pour payer, pas pour écrire à quelqu'un ni l'ajouter à ses
    /// contacts — d'où ce champ distinct, présent seulement pour un QR
    /// d'utilisateur dont le titulaire accepte d'être joint.
    ///
    /// `nil` ⇒ le QR permet au mieux de payer. Jamais reconstruit côté client
    /// depuis la charge utile : l'identité doit venir de la résolution signée.
    ///
    /// **BACKEND CONTRACT REQUIRED** — la résolution ne le rend pas encore.
    public let messagingIdentity: QRMessagingIdentity?

    public init(
        reference: FinancialReference,
        kind: QRKind,
        counterparty: FinancialActor,
        amount: Decimal? = nil,
        currency: String? = nil,
        allowedActions: Set<FinancialPermission> = [],
        expiresAt: Date? = nil,
        isExternalOrigin: Bool = false,
        messagingIdentity: QRMessagingIdentity? = nil
    ) {
        self.reference = reference
        self.kind = kind
        self.counterparty = counterparty
        self.amount = amount
        self.currency = currency
        self.allowedActions = allowedActions
        self.expiresAt = expiresAt
        self.isExternalOrigin = isExternalOrigin
        self.messagingIdentity = messagingIdentity
    }
}

/// Qui joindre dans la messagerie, tel que le backend l'a établi.
public struct QRMessagingIdentity: Sendable, Hashable, Codable {

    /// Identifiant du compte Waangu — celui qui adresse un message.
    public let userID: String

    /// Numéro sous lequel ouvrir la conversation individuelle.
    public let phoneNumber: String

    /// Nom de profil rendu par le backend. Même règle que pour
    /// `FinancialActor.displayName` : jamais résolu depuis l'annuaire local.
    public let displayName: String

    public let avatarURL: String?

    public init(userID: String, phoneNumber: String, displayName: String, avatarURL: String? = nil) {
        self.userID = userID
        self.phoneNumber = phoneNumber
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

public enum QRKind: String, Codable, Sendable, CaseIterable {
    case user, merchant, bill, moneyRequest, cashIn, cashOut

    /// Un type inconnu fait échouer le décodage.
    ///
    /// Pas de repli : rendre un QR marchand comme un QR utilisateur changerait
    /// les vérifications applicables et le libellé montré avant paiement.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = QRKind(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Type de QR inconnu : \(raw)")
            )
        }
        self = value
    }
}

// MARK: - Gardes

public extension ResolvedQR {

    func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// `true` si un paiement peut être **proposé** à partir de ce QR.
    ///
    /// Fermé par défaut, et les quatre conditions comptent ensemble : un QR
    /// périmé, révoqué, sans action de paiement ou dont la contrepartie a perdu
    /// sa vérification n'est pas « à moitié bon ».
    func allowsPayment(asOf now: Date = Date()) -> Bool {
        !isExpired(asOf: now)
            && counterparty.verification != .revoked
            && allowedActions.contains(.initiate)
    }

    /// `true` si l'utilisateur doit être averti avant toute confirmation.
    ///
    /// Un QR d'origine externe est mis en quarantaine visuelle : il n'a pas été
    /// scanné par la caméra sous les yeux de l'utilisateur, et c'est le vecteur
    /// le plus simple pour faire payer quelqu'un d'autre.
    var requiresQuarantineWarning: Bool {
        isExternalOrigin || counterparty.verification.warrantsWarning
    }
}

// MARK: - Anti-rejeu

/// Produit les valeurs à usage unique des tentatives de résolution.
///
/// Le nonce est produit **côté client** et vérifié côté serveur. L'inverse ne
/// protégerait de rien : un nonce serveur réutilisable par le client n'est
/// qu'un identifiant de plus.
public struct QRNonce: Sendable, Hashable {

    public let value: String
    public let issuedAt: Date

    public init(value: String = UUID().uuidString, issuedAt: Date = Date()) {
        self.value = value
        self.issuedAt = issuedAt
    }

    /// Deux scans ne partagent jamais un nonce, même du même QR au même instant.
    public static func fresh() -> QRNonce { QRNonce() }
}
