//
//  Money.swift
//  CoreKit
//
//  Un montant et sa devise, indissociables — Bloc 2 §0.4 et §11.1.
//

import Foundation

/// Une somme d'argent : un montant **et** la devise dans laquelle il s'exprime.
///
/// Le dépôt utilise `Decimal` partout et `Double` nulle part — l'interdiction
/// principale est donc déjà respectée, et `Decimal` est exact en base 10. Ce qui
/// manquait n'est pas la précision, c'est le lien entre le montant et sa devise :
/// deux `Decimal` nus s'additionnent sans que rien ne signale qu'il s'agit de
/// 1 000 BIF et de 1 000 CAD.
///
/// Le stockage se fait en unités mineures sur `Int64`, la représentation que les
/// rails de paiement échangent. Elle rend l'arrondi impossible à introduire par
/// inadvertance côté client : il n'y a rien à arrondir.
public struct Money: Codable, Hashable, Sendable {

    /// Montant en unités mineures. 1 500 pour 15,00 CAD ; 1 500 pour 1 500 BIF.
    public let minorUnits: Int64

    public let currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }
}

// MARK: - Arithmétique

public extension Money {

    /// Addition **totale** : deux devises différentes ne s'additionnent pas.
    ///
    /// Retourne `nil` plutôt que de lever. Un site d'appel qui additionne des
    /// devises hétérogènes a un défaut de conception, et convertir implicitement
    /// au taux du jour serait un calcul financier fait par le client — ce que
    /// l'architecture interdit explicitement.
    ///
    /// Le dépassement de capacité rend également `nil` : un total faux est pire
    /// qu'un total absent, parce qu'il s'affiche.
    func adding(_ other: Money) -> Money? {
        guard currency == other.currency else { return nil }
        let (sum, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { return nil }
        return Money(minorUnits: sum, currency: currency)
    }

    /// `true` si les deux sommes s'expriment dans la même devise.
    func isComparable(to other: Money) -> Bool { currency == other.currency }

    /// Valeur en unité majeure, **pour l'affichage uniquement**.
    ///
    /// Ne jamais réinjecter le résultat dans un calcul : c'est le chemin par
    /// lequel un arrondi d'affichage devient un montant débité.
    var majorUnitsForDisplay: Decimal {
        Decimal(minorUnits) / pow(Decimal(10), currency.exponent)
    }
}

// MARK: - CurrencyCode

/// Code ISO 4217 et son exposant décimal.
///
/// **BACKEND CONTRACT REQUIRED.** L'exposant vient du backend et n'est pas
/// dérivable côté client : BIF et RWF valent 0, CAD vaut 2, et certains rails
/// travaillent en 3. Le coder en dur produirait un facteur 100 d'erreur sur un
/// montant réel — raison pour laquelle il n'existe ici aucune table de devises
/// et aucune valeur par défaut. Tant que le backend ne rend pas l'exposant,
/// `Money` ne peut pas être construit depuis une réponse serveur, et le domaine
/// continue légitimement d'utiliser `Decimal` + code devise.
public struct CurrencyCode: Codable, Hashable, Sendable {

    /// Code alphabétique ISO 4217, normalisé en majuscules.
    public let code: String

    /// Nombre de décimales de la devise, tel que le backend l'a rendu.
    public let exponent: Int

    public init(code: String, exponent: Int) {
        self.code = code.uppercased()
        self.exponent = exponent
    }
}

extension CurrencyCode: CustomStringConvertible {
    public var description: String { code }
}
