//
//  ChatFeatureFlags.swift
//  FeatureChat
//
//  Interrupteurs de développement de la feature Chat.
//

import Foundation

/// Interrupteurs lus au démarrage par l'AppTarget.
///
/// Un seul endroit à modifier pour changer d'où viennent les données : ce
/// fichier. Aucun autre module ne décide de la provenance.
public enum ChatFeatureFlags {

    /// `true` : toute la surface financière est servie par des doublures locales
    /// (`FinanceDebugKit`) — solde, historique, cartes, factures, épargne…
    /// `false` : tout passe par WAANGU Chat Core.
    ///
    /// Un seul interrupteur pour **tous** les services : un mélange afficherait
    /// un solde réel à côté d'un historique inventé, ce qui ne se distingue pas
    /// à l'écran d'un vrai écart de compte.
    ///
    /// En `false`, un service que Chat Core n'expose pas encore est **fermé**
    /// (écran « indisponible »), jamais simulé : une donnée inventée dans un
    /// écran réel est indiscernable d'une donnée fausse venue du serveur.
    ///
    /// **Ignoré en RELEASE** : une build de production ne sert jamais de
    /// doublures, quelle que soit la valeur écrite ici.
    public nonisolated(unsafe) static var useFakeDataWallet = false
}
