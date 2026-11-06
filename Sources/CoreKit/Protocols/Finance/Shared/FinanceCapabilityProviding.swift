//
//  FinanceCapabilityProviding.swift
//  CoreKit
//
//  Fourniture du catalogue de capacités aux surfaces.

import Foundation

/// Ce que consulte une surface avant de proposer quoi que ce soit de financier.
///
/// Contrat séparé de `FinanceAPIClientProtocol` parce que les fréquences d'appel
/// diffèrent d'un ordre de grandeur : une vue interroge les capacités à chaque
/// construction, alors qu'elle lit un objet financier ponctuellement.
/// L'implémentation met en cache ; le contrat, lui, doit rester appelable
/// librement et de façon synchrone du point de vue de l'appelant.
public protocol FinanceCapabilityProviding: Sendable {

    /// Capacités courantes. Ne lève jamais : toute erreur donne `.none`.
    ///
    /// L'absence de `throws` est un choix de sûreté. Un `try?` sur un appel
    /// faillible produit `nil`, et un site d'appel finit toujours par écrire
    /// `?? .allEnabled` « le temps de déboguer ». En rendant l'échec
    /// indistinguable de « rien n'est autorisé », l'API ne laisse pas cette porte.
    func capabilities() async -> FinanceCapabilities

    /// Force une résolution auprès du backend, en ignorant le cache.
    /// À appeler sur changement de compte, de pays ou de niveau KYC.
    func invalidate() async
}

// MARK: - Confort

public extension FinanceCapabilityProviding {

    /// `true` si la surface financière doit être proposée dans une conversation.
    ///
    /// L'affichage des cartes reçues et l'émission sont dissociés : un marché peut
    /// autoriser la réception d'un paiement sans en autoriser l'émission.
    func canRenderFinancialCards() async -> Bool {
        await capabilities().effective().viewFinancialCards
    }

    /// `true` si au moins une action financière est ouverte depuis le composer.
    func canInitiateFromComposer() async -> Bool {
        await capabilities().effective().allowsAnyOutgoingOperation
    }
}
