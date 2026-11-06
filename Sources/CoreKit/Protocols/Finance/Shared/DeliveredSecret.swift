//
//  DeliveredSecret.swift
//  CoreKit
//
//  Jetons, vouchers et codes livrés — Bloc 4, chapitre 29 (GAP-03).
//

import Foundation

/// Un secret livré par un fournisseur : jeton d'énergie, voucher, code PIN de
/// recharge.
///
/// **Porteur de valeur.** Comme le code de retrait du Bloc 3 : quiconque le lit
/// peut consommer le service. Les mêmes protections s'appliquent, et elles sont
/// portées par le type plutôt que par la discipline de chaque site d'appel.
///
/// Le type ne conforme **délibérément pas** à `Codable` : le rendre encodable
/// inviterait à le persister, et un jeton d'énergie sur disque est un billet
/// dans un tiroir ouvert. Il vit en mémoire, le temps d'être révélé.
public struct DeliveredSecret: Sendable, Equatable {

    public let deliveryID: String
    public let reference: FinancialReference
    public let kind: DeliveredSecretKind

    /// La valeur complète. **Jamais journalisée, persistée ni notifiée.**
    public let value: String

    /// Ce que le secret donne. Affiché avec lui pour que l'utilisateur vérifie
    /// avant de le saisir sur un compteur.
    public let subjectLabel: String
    public let amount: Money?

    public let issuedAt: Date
    public let expiresAt: Date?

    public init(
        deliveryID: String, reference: FinancialReference, kind: DeliveredSecretKind,
        value: String, subjectLabel: String, amount: Money? = nil,
        issuedAt: Date, expiresAt: Date? = nil
    ) {
        self.deliveryID = deliveryID
        self.reference = reference
        self.kind = kind
        self.value = value
        self.subjectLabel = subjectLabel
        self.amount = amount
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

extension DeliveredSecret: CustomStringConvertible {

    /// Description **sans la valeur**.
    ///
    /// Une interpolation dans un `print` ou un log est la manière la plus banale
    /// de faire fuir un porteur de valeur. Le type refuse de se décrire en
    /// entier plutôt que de compter sur la vigilance de chaque appelant.
    public var description: String {
        "DeliveredSecret(\(kind.rawValue), \(deliveryID), value: <redacted>)"
    }
}

public enum DeliveredSecretKind: String, Codable, Sendable, CaseIterable {
    case electricityToken = "ELECTRICITY_TOKEN"
    case voucher          = "VOUCHER"
    case rechargePIN      = "RECHARGE_PIN"
    case accessCode       = "ACCESS_CODE"
}

// MARK: - Politique de révélation

/// Ce qui est permis autour d'un secret livré.
///
/// **BACKEND SOURCE OF TRUTH.** Un jeton d'énergie de 50 000 et un voucher de
/// 500 n'appellent pas les mêmes précautions, et le client ne connaît ni les
/// règles du marché ni le profil de risque.
public struct SecretRevealPolicy: Codable, Sendable, Hashable {

    public let requireBiometric: Bool
    /// Masquage automatique après affichage. `0` ⇒ pas de masquage automatique.
    public let autoHideAfter: TimeInterval
    public let allowCopy: Bool
    public let allowShare: Bool

    public init(requireBiometric: Bool, autoHideAfter: TimeInterval,
                allowCopy: Bool, allowShare: Bool) {
        self.requireBiometric = requireBiometric
        self.autoHideAfter = autoHideAfter
        self.allowCopy = allowCopy
        self.allowShare = allowShare
    }

    /// Politique la plus stricte. Repli en toute circonstance douteuse.
    ///
    /// Biométrie exigée, masquage à 30 s, ni copie ni partage. Un secret qu'on
    /// n'a pas su classer est traité comme le plus sensible — l'inverse
    /// exposerait le plus précieux par défaut.
    public static let strict = SecretRevealPolicy(
        requireBiometric: true, autoHideAfter: 30,
        allowCopy: false, allowShare: false
    )
}

public extension DeliveredSecret {

    func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Version masquée, pour tout affichage **hors** de l'écran de révélation.
    ///
    /// Les jetons d'énergie sont longs (20 chiffres) : montrer les quatre
    /// derniers suffit à reconnaître le sien sans le rendre utilisable.
    var maskedValue: String {
        let visible = 4
        guard value.count > visible else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: value.count - visible) + value.suffix(visible)
    }

    /// Découpe pour l'affichage et la dictée. Un jeton de 20 chiffres se saisit
    /// sur un compteur : par groupes de quatre, il se relit sans se perdre.
    var groupedValue: String {
        stride(from: 0, to: value.count, by: 4).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: min(4, value.count - offset))
            return String(value[start..<end])
        }.joined(separator: " ")
    }

    /// VoiceOver épelle chiffre par chiffre.
    ///
    /// Lu d'un bloc, un jeton devient un nombre astronomique — inutilisable
    /// pour le saisir sur un compteur.
    var spelledValue: String { value.map(String.init).joined(separator: " ") }
}
