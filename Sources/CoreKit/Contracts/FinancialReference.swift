//
//  FinancialReference.swift
//  CoreKit
//
//  Identité et révision d'un objet financier.
//
//  Le client n'est jamais l'auteur d'un objet financier : il en détient une copie,
//  datée par `version`. Sans cette version, deux événements arrivés dans le désordre
//  — ce que MQTT autorise explicitement à la reconnexion — sont indiscernables, et
//  le plus ancien écrase le plus récent.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.2.

import Foundation

// MARK: - FinancialObjectType

/// Nature de l'objet financier référencé.
///
/// Le type fait partie de l'identité : deux objets peuvent partager un identifiant
/// sans être le même objet s'ils proviennent de rails différents.
///
/// **Taxonomie commune aux clients** (iOS, Android, Web) : la valeur brute voyage
/// dans `financialObjectType` des messages `ISMONEY`, et choisit la carte du
/// destinataire. Elle remplace les dix cas du Bloc 1 §5.1 — `transfer` et
/// `recharge` n'y existent plus : un envoi est un `PAYMENT`, une recharge est
/// `AIRTIME` ou `DATA_BUNDLE`.
///
/// `SPLIT_BILL` est ajouté à la liste reçue : Chat Core expose le partage comme
/// une ressource propre (`/split-bill/{splitRef}`), distincte d'une demande.
public enum FinancialObjectType: String, Codable, Sendable, CaseIterable {
    case moneyRequest = "MONEY_REQUEST"
    case payment = "PAYMENT"
    case bill = "BILL"
    case airtime = "AIRTIME"
    case dataBundle = "DATA_BUNDLE"
    case remittance = "REMITTANCE"
    case fxQuote = "FX_QUOTE"
    case merchantPayment = "MERCHANT_PAYMENT"
    case cashIn = "CASH_IN"
    case cashOut = "CASH_OUT"
    case refund = "REFUND"
    case dispute = "DISPUTE"
    case credit = "CREDIT"
    case investment = "INVESTMENT"
    case savings = "SAVINGS"
    case card = "CARD"
    case settlement = "SETTLEMENT"
    case payout = "PAYOUT"
    case splitBill = "SPLIT_BILL"
    case unknown

    /// Une valeur qu'un client plus récent connaît et pas celui-ci devient
    /// `unknown` au lieu de faire échouer tout le décodage : la carte générique
    /// reste affichable, rien n'est deviné.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FinancialObjectType(rawValue: raw) ?? .unknown
    }

    /// Nature connue de ce client — la seule sous laquelle une lecture serveur
    /// peut partir. `unknown` n'est pas une nature : c'est l'aveu qu'on l'ignore.
    public var isKnown: Bool { self != .unknown }
}

// MARK: - FinancialReference

/// Référence versionnée vers un objet financier détenu par le backend.
///
/// Ne porte **aucune** donnée métier : ni montant, ni devise, ni contrepartie, ni
/// statut. C'est délibéré — une référence circule (deep link, push, message), et
/// tout ce qui circule est falsifiable. Les données se lisent auprès du backend.
public struct FinancialReference: Codable, Sendable, Hashable {

    /// Nature de l'objet.
    public let type: FinancialObjectType

    /// Identifiant opaque émis par le backend. Sans signification métier côté client.
    public let id: String

    /// Révision de l'objet, strictement croissante côté backend.
    ///
    /// C'est la seule chose qui permet d'ordonner deux copies du même objet.
    public let version: Int

    /// Trace l'opération à travers les services. Voir `CorrelationId`.
    public let correlationID: CorrelationId

    public init(
        type: FinancialObjectType,
        id: String,
        version: Int,
        correlationID: CorrelationId
    ) {
        self.type = type
        self.id = id
        self.version = version
        self.correlationID = correlationID
    }
}

// MARK: - Identité

public extension FinancialReference {

    /// Deux références désignent le même objet si type et id coïncident —
    /// indépendamment de la version et de la corrélation.
    ///
    /// `Hashable` ne peut pas servir à cela : deux copies du même objet à des
    /// versions différentes doivent être distinguables dans un cache, tout en
    /// étant reconnues comme le même objet ici.
    func identifies(_ other: FinancialReference) -> Bool {
        type == other.type && id == other.id
    }

    /// Clé d'identité stable, sans la version.
    var identityKey: String { "\(type.rawValue):\(id)" }
}

// MARK: - Résolution de conflit

public extension FinancialReference {

    /// `true` si cette référence est strictement plus récente que `other`.
    ///
    /// Politique unique de résolution de conflit du Bloc 1 :
    ///
    /// ```
    /// version = 8  ne remplace jamais  version = 9
    /// version = 9  ne remplace jamais  version = 9
    /// ```
    ///
    /// L'égalité est volontairement refusée. Un événement rejoué porte la même
    /// version que celui déjà appliqué : le réappliquer n'apporte rien et peut
    /// relancer des effets de bord (animation, notification, analytics).
    ///
    /// Une référence portant sur un **autre** objet ne remplace jamais celle-ci,
    /// quelle que soit sa version — d'où le contrôle d'identité préalable.
    func supersedes(_ other: FinancialReference) -> Bool {
        guard identifies(other) else { return false }
        return version > other.version
    }

    /// Inverse de `supersedes`, pour le site d'appel qui raisonne côté événement
    /// entrant plutôt que côté état courant.
    ///
    /// Un événement portant sur un autre objet est « périmé » ici : il ne doit pas
    /// être appliqué à *cet* état. Le dispatch vers le bon état est la
    /// responsabilité de l'appelant, pas de ce prédicat.
    func isStale(comparedTo current: FinancialReference) -> Bool {
        !supersedes(current)
    }
}

// MARK: - CustomStringConvertible

extension FinancialReference: CustomStringConvertible {

    /// Volontairement sans l'identifiant brut : cette description finit dans des
    /// logs. Voir `FinanceLogContext` pour le contexte journalisable complet.
    public var description: String {
        "FinancialReference(\(type.rawValue), v\(version))"
    }
}
