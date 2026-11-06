//
//  CopilotConversationHost.swift
//  FeatureChat
//
//  Ce que la conversation d'où l'on ouvre Waangu Copilot est seule à savoir.
//

import WaanguCoreKit

/// La conversation qui porte Waangu Copilot, quand il est ouvert depuis un fil.
///
/// Hors conversation (Réglages, portefeuille), il n'y en a pas : Copilot
/// propose alors les contacts, et rien n'est annoncé dans un fil.
struct CopilotConversationHost {
    /// Fil où l'opération s'annonce, et que porte le prepare.
    let conversationID: String
    /// L'interlocuteur, proposé en premier comme bénéficiaire. `nil` dans un groupe.
    let peer: RecipientInput?
    /// Nom sous lequel l'utilisateur connaît l'interlocuteur — indication pour le
    /// résolveur, jamais affichée à la place du nom qu'il rend.
    let peerName: String?
    /// Utilisateur Chat de l'interlocuteur — la partie d'une demande d'argent.
    var peerChatUserID: String? = nil
    /// Les demandes d'argent reçues dans ce fil — leurs références seulement ; l'état
    /// (ouverte, payable, refusable) se relit toujours au serveur.
    var receivedRequests: @MainActor () -> [FinancialReference] = { [] }
    /// Annonce la référence produite dans le fil, comme le fait l'écran ordinaire.
    var publish: @MainActor (FinancialReference, String?) async -> Bool
}
