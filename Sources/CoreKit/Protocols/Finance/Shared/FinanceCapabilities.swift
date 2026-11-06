//
//  FinanceCapabilities.swift
//  CoreKit
//
//  Catalogue des capacités financières autorisées, décidé par le backend.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §13 et §15 (contrat backend #5).

import Foundation

/// Ce que l'utilisateur courant a le droit de faire, ici et maintenant.
///
/// Le client ne calcule jamais ce catalogue : il le reçoit. Une capacité dépend du
/// pays, du tenant, du niveau KYC, du score de risque, de la licence détenue sur ce
/// marché, du canal et de la version d'application — autant de dimensions dont le
/// client n'a ni la donnée ni l'autorité.
///
/// **Fermé par défaut.** Toute construction implicite donne `.none`. Un catalogue
/// absent, illisible ou expiré n'active rien. C'est la protection qui tient tant
/// que les contrats backend de signature ne sont pas livrés : le code de la surface
/// financière peut exister intégralement sans qu'aucune action ne soit atteignable.
public struct FinanceCapabilities: Codable, Sendable, Hashable {

    public let sendMoney: Bool
    public let requestMoney: Bool
    public let qrPayment: Bool
    public let merchantPayment: Bool
    public let splitPayment: Bool
    public let billPayment: Bool
    public let recharge: Bool
    public let fx: Bool
    public let remittance: Bool

    /// Affichage seul : rendre les cartes financières reçues, sans pouvoir en émettre.
    ///
    /// Séparé des capacités d'émission à dessein — c'est le périmètre P0 du Bloc 1,
    /// et il doit pouvoir être activé sans ouvrir aucun chemin d'écriture.
    public let viewFinancialCards: Bool

    /// Ce pour quoi ce catalogue a été résolu.
    /// Un catalogue résolu pour un autre contexte ne s'applique pas.
    public let context: FinanceCapabilityContext

    /// Signature backend du catalogue. `nil` tant que le contrat #5 n'est pas livré.
    public let signature: String?

    /// Fin de validité. Un catalogue expiré vaut `.none`, il ne se prolonge pas.
    public let expiresAt: Date?

    public init(
        sendMoney: Bool = false,
        requestMoney: Bool = false,
        qrPayment: Bool = false,
        merchantPayment: Bool = false,
        splitPayment: Bool = false,
        billPayment: Bool = false,
        recharge: Bool = false,
        fx: Bool = false,
        remittance: Bool = false,
        viewFinancialCards: Bool = false,
        context: FinanceCapabilityContext = .unknown,
        signature: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.sendMoney = sendMoney
        self.requestMoney = requestMoney
        self.qrPayment = qrPayment
        self.merchantPayment = merchantPayment
        self.splitPayment = splitPayment
        self.billPayment = billPayment
        self.recharge = recharge
        self.fx = fx
        self.remittance = remittance
        self.viewFinancialCards = viewFinancialCards
        self.context = context
        self.signature = signature
        self.expiresAt = expiresAt
    }
}

// MARK: - Décodage fermé par défaut

public extension FinanceCapabilities {

    /// Une clé absente vaut `false`, jamais une erreur de décodage.
    ///
    /// Le décodage synthétisé échouerait sur la première capacité manquante et
    /// ferait perdre **tout** le catalogue — y compris les capacités correctement
    /// transmises. Ici l'inconnu est simplement refusé, ce qui va dans le sens sûr.
    ///
    /// Ce choix n'est acceptable que parce que le défaut est `false`. Le même
    /// décodage tolérant avec un défaut `true` serait une porte ouverte.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool {
            (try? c.decode(Bool.self, forKey: key)) ?? false
        }
        self.init(
            sendMoney:          flag(.sendMoney),
            requestMoney:       flag(.requestMoney),
            qrPayment:          flag(.qrPayment),
            merchantPayment:    flag(.merchantPayment),
            splitPayment:       flag(.splitPayment),
            billPayment:        flag(.billPayment),
            recharge:           flag(.recharge),
            fx:                 flag(.fx),
            remittance:         flag(.remittance),
            viewFinancialCards: flag(.viewFinancialCards),
            context:            (try? c.decode(FinanceCapabilityContext.self, forKey: .context)) ?? .unknown,
            signature:          try? c.decode(String.self, forKey: .signature),
            expiresAt:          try? c.decode(Date.self, forKey: .expiresAt)
        )
    }
}

// MARK: - Constantes et évaluation

public extension FinanceCapabilities {

    /// Aucune capacité. Valeur de repli en toute circonstance douteuse :
    /// réseau indisponible, catalogue illisible, signature absente, contexte périmé.
    static let none = FinanceCapabilities()

    /// `true` si le catalogue est encore valide à l'instant donné.
    /// Un catalogue sans `expiresAt` est traité comme valide — c'est au backend de
    /// borner sa durée de vie, pas au client de l'inventer.
    func isValid(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }

    /// Le catalogue effectif : lui-même s'il est valide, `.none` sinon.
    ///
    /// À interposer systématiquement entre le cache et la décision d'affichage,
    /// pour qu'un catalogue expiré ne survive pas à un relaunch hors ligne.
    func effective(asOf now: Date = Date()) -> FinanceCapabilities {
        isValid(asOf: now) ? self : .none
    }

    /// `true` si au moins une capacité d'**émission** est ouverte.
    /// L'affichage seul n'en fait pas partie.
    var allowsAnyOutgoingOperation: Bool {
        sendMoney || requestMoney || qrPayment || merchantPayment
            || splitPayment || billPayment || recharge || fx || remittance
    }
}

// MARK: - FinanceCapabilityContext

/// Les dimensions pour lesquelles un catalogue a été résolu.
///
/// Sert à invalider le cache dès qu'une d'elles change — changement de pays, montée
/// de niveau KYC, bascule de tenant. Sans cela, un utilisateur qui change de pays
/// conserverait les capacités du précédent.
public struct FinanceCapabilityContext: Codable, Sendable, Hashable {

    public let country: String?
    public let tenantID: String?
    public let userID: String?
    public let kycLevel: String?
    public let riskTier: String?
    public let channel: String?
    public let appVersion: String?

    public init(
        country: String? = nil,
        tenantID: String? = nil,
        userID: String? = nil,
        kycLevel: String? = nil,
        riskTier: String? = nil,
        channel: String? = nil,
        appVersion: String? = nil
    ) {
        self.country = country
        self.tenantID = tenantID
        self.userID = userID
        self.kycLevel = kycLevel
        self.riskTier = riskTier
        self.channel = channel
        self.appVersion = appVersion
    }

    /// Contexte non résolu. Ne correspond à aucun contexte réel — y compris
    /// à lui-même, pour qu'un catalogue jamais résolu ne soit jamais réutilisé.
    public static let unknown = FinanceCapabilityContext()

    /// `true` si un catalogue résolu pour `self` s'applique encore à `other`.
    public func matches(_ other: FinanceCapabilityContext) -> Bool {
        guard self != .unknown, other != .unknown else { return false }
        return self == other
    }
}
