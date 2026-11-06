//
//  ChatModule.swift
//  FeatureChat
//
//  Les parties du Chat qu'un hôte peut activer ou non (plan SDK, étape 1.10, D-04).
//

import SwiftUI

/// Une partie du Chat que l'hôte demande ou non. La messagerie est toujours là : elle n'est pas
/// dans cette liste.
///
/// Une partie absente ne montre aucun point d'entrée : pas d'onglet, pas de bouton. L'hôte
/// décide seul ; seul `payments` est en plus soumis à la réponse du serveur (les capacités).
/// Un appel entrant, lui, n'est pas retiré par `calls` : il vient du gestionnaire VoIP.
/// Les groupes ne sont pas une partie à part : leurs écrans sont répartis dans la messagerie.
public enum ChatModule: String, CaseIterable, Sendable {
    /// Onglet Appels, boutons d'appel, moteur d'appel.
    case calls
    /// Onglet Actualités : les statuts **et** les canaux, qui y vivent. Sans lui, un lien vers
    /// un canal ou une invitation est ignoré.
    case status
    /// Onglet Communautés et canaux.
    case communities
    /// Paiements dans les conversations.
    case payments

    /// Ce qu'un hôte reçoit s'il ne demande rien : tout, sauf les paiements.
    public static let standard: Set<ChatModule> = [.calls, .status, .communities]

    /// Toutes les parties. C'est le défaut de `ChatDependencies` : un appelant qui ne dit rien
    /// garde le comportement d'avant.
    public static let all: Set<ChatModule> = Set(allCases)
}

// MARK: - Environment

private struct ChatEnabledModulesKey: EnvironmentKey {
    static let defaultValue: Set<ChatModule> = ChatModule.all
}

extension EnvironmentValues {
    /// Les parties activées, posées à la racine du Chat. Un écran qui offre un point d'entrée
    /// d'une partie la lit ici.
    var chatEnabledModules: Set<ChatModule> {
        get { self[ChatEnabledModulesKey.self] }
        set { self[ChatEnabledModulesKey.self] = newValue }
    }
}
