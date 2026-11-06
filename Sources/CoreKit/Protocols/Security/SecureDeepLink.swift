//
//  SecureDeepLink.swift
//  CoreKit
//
//  Bloc 9, §15 — validation des liens profonds avant toute action.
//

import Foundation

/// Un lien profond dont les paramètres de sécurité ont été extraits.
///
/// Le `DeepLinkParser` actuel valide l'hôte contre une liste, puis extrait des
/// identifiants bruts. C'est suffisant tant qu'aucune route ne mène à une action
/// financière — ce qui est le cas aujourd'hui, **par absence de route et non par
/// contrôle**. La première route financière ajoutée ouvrirait la faille sans que
/// rien ne le signale.
public struct SecureDeepLink: Sendable, Equatable {

    public let route: String
    public let objectID: String

    /// Valeur à usage unique, émise par le serveur.
    public let nonce: String?

    /// Échéance du lien.
    public let expiresAt: Date?

    /// Signature serveur couvrant route, objet, nonce et échéance.
    public let signature: String?

    public init(
        route: String,
        objectID: String,
        nonce: String? = nil,
        expiresAt: Date? = nil,
        signature: String? = nil
    ) {
        self.route = route
        self.objectID = objectID
        self.nonce = nonce
        self.expiresAt = expiresAt
        self.signature = signature
    }
}

/// Niveau d'exigence d'une route.
///
/// Le point de ce type : rendre l'exigence **explicite par route**, de sorte
/// qu'ajouter une route financière oblige à choisir son niveau. Un défaut
/// implicite ferait hériter la nouvelle route du régime le plus permissif, ce
/// qui est exactement la façon dont ce genre de faille apparaît.
public enum DeepLinkTrustRequirement: Sendable, Equatable {

    /// Navigation pure. Aucune donnée n'est modifiée, aucune valeur déplacée.
    case navigationOnly

    /// Consultation de données personnelles — exige une session valide.
    case authenticated

    /// Action financière — exige signature, nonce, échéance **et**
    /// revalidation serveur avant toute présentation.
    case financial
}

/// Raison du rejet d'un lien.
public enum DeepLinkRejection: Error, Sendable, Equatable {
    case unknownRoute(String)
    case missingSignature(route: String)
    case missingNonce(route: String)
    case expired(route: String)
    case replayed(nonce: String)
    case signatureInvalid(route: String)
}

/// Valide un lien profond avant qu'il n'atteigne la navigation.
public protocol DeepLinkValidating: Sendable {

    /// Lève si le lien ne satisfait pas les exigences de sa route.
    ///
    /// Lève plutôt que de rendre un `Bool` : un appelant qui ignore un booléen
    /// compile, et le lien non validé poursuit sa route.
    func validate(
        _ link: SecureDeepLink,
        requirement: DeepLinkTrustRequirement
    ) async throws
}
