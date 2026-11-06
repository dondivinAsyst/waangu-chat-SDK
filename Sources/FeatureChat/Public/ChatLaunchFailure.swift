//
//  ChatLaunchFailure.swift
//  FeatureChat
//
//  Échec d'ouverture du Chat — Harness §6 (isolation des pannes), B02.
//

import Foundation

/// Le Chat n'a pas pu s'ouvrir.
///
/// Avant ce type, l'échec était imprimé dans la console et le geste de
/// l'utilisateur ne faisait rien : pas d'écran de repli, pas de trace, pas de
/// nouvel essai. La Super App reste utilisable ; ce type dit à l'utilisateur
/// ce qui s'est passé et garde l'ouverture demandée pour la rejouer.
public struct ChatLaunchFailure: Error, Equatable, Sendable, Identifiable {

    /// L'ouverture demandée, rejouée telle quelle par « Réessayer ».
    public let launch: ChatLaunchContext

    /// Le type de l'erreur d'origine — jamais son message, qui peut porter une
    /// URL ou un identifiant.
    public let errorType: String

    /// Ce que l'hôte peut en faire (§16.1) : réessayer, reconnecter, se taire.
    public let category: ChatErrorCategory

    public let id: UUID

    public init(launch: ChatLaunchContext, error: Error, id: UUID = UUID()) {
        self.launch = launch
        self.errorType = String(describing: type(of: error))
        self.category = ChatErrorCategory(error)
        self.id = id
    }

    /// Ligne de journal **sans contenu** (§88) : provenance, nature de la
    /// destination, catégorie et type d'erreur. Aucun identifiant de conversation,
    /// d'objet, de jeton ni d'invitation.
    public var logLine: String {
        "chat_launch_failed source=\(launch.source.rawValue) destination=\(launch.route.kind) category=\(category.rawValue) error=\(errorType)"
    }
}

extension ChatRoute {

    /// Nature de la destination, sans ses paramètres — pour les journaux.
    public var kind: String {
        switch self {
        case .chats:           return "chats"
        case .updates:         return "updates"
        case .communities:     return "communities"
        case .calls:           return "calls"
        case .settings:        return "settings"
        case .share:           return "share"
        case .conversation:    return "conversation"
        case .financialObject: return "financialObject"
        case .paymentLink:     return "paymentLink"
        case .channelInvite:   return "channelInvite"
        case .channel:         return "channel"
        }
    }
}
