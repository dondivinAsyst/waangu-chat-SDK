//
//  QRPresenting.swift
//  CoreKit
//
//  Présentation d'un QR pour se faire payer — Bloc 1, chapitre 7.
//
//  **BACKEND CONTRACT REQUIRED** — émission, rotation, révocation.
//

import Foundation

/// Émet un QR que **l'utilisateur présente** pour être payé.
///
/// Le pendant de ``QRResolving``, qui lui traite les QR scannés. Les deux sens
/// sont séparés parce qu'ils n'ont pas les mêmes risques : scanner expose à un
/// QR falsifié, présenter expose à la **rejouabilité** du sien.
///
/// La charge utile n'est jamais composée ici. Un QR de paiement fabriqué côté
/// client est un QR que n'importe qui peut fabriquer : c'est le backend qui
/// signe, et lui seul peut révoquer.
public protocol QRPresenting: Sendable {

    /// Demande un QR signé. Chaque appel produit une charge utile neuve.
    func issue(_ request: QRPresentationRequest) async -> Result<PresentableQR, FinanceError>

    /// Invalide immédiatement un QR émis — écran fermé, montant modifié,
    /// paiement reçu. Sans cela, un QR photographié reste payable.
    func revoke(_ id: String) async -> Result<Void, FinanceError>
}

// MARK: - Demande

public struct QRPresentationRequest: Sendable, Hashable, Codable {

    /// Ce que le QR permet de faire. Un QR d'identité et un QR d'encaissement
    /// n'exposent pas la même chose et ne se substituent pas l'un à l'autre.
    public let kind: QRKind

    /// Montant **exact** attendu, quand il est connu. `nil` ⇒ le payeur saisit
    /// le montant, ce que le backend doit accepter explicitement pour ce type.
    public let amount: Money?

    /// Motif visible du payeur. Jamais un secret : un QR se photographie.
    public let labelKey: String?

    /// Rattache l'encaissement à une conversation, pour que la carte
    /// financière atterrisse au bon endroit.
    public let conversationID: String?

    public init(kind: QRKind, amount: Money? = nil,
                labelKey: String? = nil, conversationID: String? = nil) {
        self.kind = kind
        self.amount = amount
        self.labelKey = labelKey
        self.conversationID = conversationID
    }
}

// MARK: - Le QR émis

public struct PresentableQR: Sendable, Hashable, Codable, Identifiable {

    public let id: String

    /// Charge utile signée, à encoder telle quelle. **Opaque** : la découper,
    /// la reformater ou la reconstruire invalide la signature.
    public let payload: String

    public let kind: QRKind
    public let amount: Money?

    /// Référence lisible, à dicter quand le scan échoue. Elle identifie
    /// l'encaissement attendu ; elle n'autorise aucun débit à elle seule.
    public let humanReference: String?

    public let issuedAt: Date

    /// Après quoi le QR n'est plus payable.
    public let expiresAt: Date

    /// Quand demander une charge utile neuve, **avant** l'expiration.
    ///
    /// Un QR affiché longtemps finit photographié. La rotation borne la fenêtre
    /// pendant laquelle une photo reste utilisable ; `nil` ⇒ le backend ne fait
    /// pas tourner ce type de QR, et l'écran ne l'invente pas.
    public let rotateAfter: TimeInterval?

    public init(id: String, payload: String, kind: QRKind, amount: Money? = nil,
                humanReference: String? = nil, issuedAt: Date, expiresAt: Date,
                rotateAfter: TimeInterval? = nil) {
        self.id = id
        self.payload = payload
        self.kind = kind
        self.amount = amount
        self.humanReference = humanReference
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.rotateAfter = rotateAfter
    }

    /// Un QR expiré ne doit plus s'afficher : le présenter ferait attendre
    /// quelqu'un devant un code que le backend refusera.
    public func isValid(at now: Date = Date()) -> Bool { now < expiresAt }

    /// Le moment de demander une charge utile neuve.
    public func needsRotation(at now: Date = Date()) -> Bool {
        guard let rotateAfter else { return false }
        return now.timeIntervalSince(issuedAt) >= rotateAfter
    }
}

// MARK: - Défaut fermé

/// Refuse tout tant qu'aucune implémentation n'est branchée.
///
/// Le défaut ne fabrique pas de QR de test : un faux QR affiché en production
/// est un encaissement qui n'arrivera jamais, sans que personne le voie.
public struct ClosedQRPresenter: QRPresenting {

    public init() {}

    public func issue(_ request: QRPresentationRequest) async -> Result<PresentableQR, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func revoke(_ id: String) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
