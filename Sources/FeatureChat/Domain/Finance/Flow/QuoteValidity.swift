//
//  QuoteValidity.swift
//  FeatureChat
//
//  Cycle de vie d'un devis à l'écran — Bloc 10, chapitre 80 §8.
//

import Foundation

/// valide → expire bientôt → expiré → actualisation requise.
///
/// `isExpired()` ne répondait qu'au moment où l'écran se dessinait : un devis
/// affiché, laissé ouvert, expirait sans que rien ne bouge, et le bouton de
/// confirmation restait actif. Le cas d'usage refusait bien la soumission, mais
/// l'utilisateur lisait un échec au lieu d'une invitation à actualiser.
///
/// Pur et sans horloge : l'instant est passé en paramètre, pour que les courses
/// temporelles se testent sans attendre.
enum QuoteValidity: Equatable, Sendable {
    case valid
    /// Il reste moins de ``expiringThreshold`` secondes.
    case expiring(secondsLeft: Int)
    /// Le devis ne peut plus être confirmé : il faut en demander un nouveau.
    case expired

    /// En dessous de ce délai, l'écran prévient.
    static let expiringThreshold: TimeInterval = 30

    static func at(_ now: Date, expiresAt: Date,
                   threshold: TimeInterval = expiringThreshold) -> QuoteValidity {
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining <= 0 { return .expired }
        if remaining <= threshold { return .expiring(secondsLeft: Int(remaining.rounded(.up))) }
        return .valid
    }

    /// Seul l'état expiré interdit de confirmer. Un devis qui expire bientôt se
    /// confirme encore — le cas d'usage revérifie de toute façon à l'exécution.
    var allowsConfirmation: Bool { self != .expired }
}
