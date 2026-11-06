//
//  ChatLaunchContext.swift
//  FeatureChat
//
//  Contrat d'ouverture du Chat depuis la Super App — tâche 7.8.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §12.2.

import Foundation
import WaanguCoreKit

/// Ce sur quoi le Chat doit s'ouvrir.
///
/// Le partage des responsabilités est déjà celui du dépôt : la Super App possède
/// session, identité, navigation globale, thème et cycle de vie ; le Chat possède
/// conversation, messages, composer et cartes. Ce type est la frontière entre les
/// deux pour l'ouverture.
///
/// **Toute** ouverture du Chat passe par ce type (Harness §3, B01) : l'AppTarget
/// ne présente plus le Chat sur une `ChatRoute` nue, dont on ne savait pas d'où
/// elle venait.
///
/// Les destinations financières sont portées **par référence** et non par
/// valeur : `ChatRoute` n'a aucun cas capable de transporter un montant ou un
/// statut. Un contexte qui en transporterait permettrait à l'appelant de décider
/// ce qui s'affiche. Ici il désigne, et le Chat relit au serveur — quelle que
/// soit la source.
///
/// Les champs d'identité, de session, de pays et de version du contrat Host
/// (§3) ne sont pas encore ici : leur propriétaire n'est pas désigné (B20).
public struct ChatLaunchContext: Sendable, Equatable {

    /// Où le Chat s'ouvre.
    public let route: ChatRoute

    /// D'où vient l'ouverture.
    public let source: ChatEntrySource

    /// `route` est obligatoire : avec une valeur par défaut, `init(source:)`
    /// serait ambigu avec l'initialiseur historique ci-dessous.
    public init(route: ChatRoute, source: ChatEntrySource) {
        self.route = route
        self.source = source
        self.legacyFinancialReference = nil
    }

    // MARK: - API historique (paquet publié)
    //
    // Le paquet est republié et tiré par d'autres projets : l'API d'avant le
    // 2026-10-05 reste disponible, dépréciée, et se traduit en `route`.

    /// Référence passée à l'initialiseur historique, rendue telle quelle.
    private let legacyFinancialReference: FinancialReference?

    @available(*, deprecated, message: "Use init(route:source:).")
    public init(
        conversationID: String? = nil,
        financialReference: FinancialReference? = nil,
        source: ChatEntrySource
    ) {
        if let financialReference {
            self.route = .financialObject(opaqueId: financialReference.id,
                                          objectType: financialReference.type.rawValue)
        } else if let conversationID {
            self.route = .conversation(id: conversationID)
        } else {
            self.route = .chats
        }
        self.source = source
        self.legacyFinancialReference = financialReference
    }

    @available(*, deprecated, message: "Read route instead.")
    public var conversationID: String? {
        if case .conversation(let id) = route { return id }
        return nil
    }

    /// Seulement ce qui a été passé à l'initialiseur historique : la version et
    /// la corrélation d'une référence ne se reconstruisent pas depuis `route`.
    @available(*, deprecated, message: "Read route instead.")
    public var financialReference: FinancialReference? { legacyFinancialReference }

    /// `true` si la destination désigne un objet ou un lien financier.
    public var designatesFinancialObject: Bool {
        switch route {
        case .financialObject, .paymentLink: return true
        default:                             return false
        }
    }
}

/// Provenance d'une ouverture du Chat.
///
/// Utile au-delà de la télémétrie : une ouverture par `push` ou `deepLink` n'est
/// pas fiable au même titre qu'une ouverture par `tab`, et impose une lecture
/// serveur avant tout affichage financier.
public enum ChatEntrySource: String, Sendable, Equatable, CaseIterable {
    case tab
    case deepLink
    case push
    case wallet
    case share
    case notificationCenter

    /// `true` si l'ouverture vient d'une source non fiable, dont le contenu ne
    /// doit jamais être promu en vérité.
    public var requiresServerResolution: Bool {
        switch self {
        case .push, .deepLink: return true
        default:               return false
        }
    }
}
