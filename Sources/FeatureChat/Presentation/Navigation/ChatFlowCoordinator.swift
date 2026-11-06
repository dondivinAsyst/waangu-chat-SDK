//
//  ChatFlowCoordinator.swift
//  FeatureChat
//
//  Created by Refactoring on 5/5/26.
//

import WaanguNavigationKit
import Combine
import Foundation
import SwiftUI
import WaanguCoreKit



@MainActor
public final class ChatCoordinator: ObservableObject {
    @Published var selectedTab: Tab = .chats
    @Published var isAuthenticated: Bool = false
    @Published var isPresentingShare: Bool = false
    @Published var sharedContentUrl: URL?

    /// Objet financier à présenter, ouvert depuis un push.
    @Published var presentedFinancialObject: PresentedFinancialObject?
    /// Lien de paiement ouvert de l'extérieur, en cours d'inspection.
    @Published var presentedPaymentLink: PresentedPaymentLink?
    /// Invitation à un canal ouverte par lien, en cours d'aperçu.
    @Published var presentedChannelInvite: PresentedChannelInvite?

    /// AppTarget wires this to dismiss the chat modal and handle cross-feature navigation.
    public var onCrossFeature: ((NavigationIntent) -> Void)?

    // New coordinators following NavigationKit pattern
    public let chatsTabCoordinator: ChatsTabCoordinator
    public  let updatesTabCoordinator: UpdatesTabCoordinator
    public let callsTabCoordinator: CallsTabCoordinator
    public  let communitiesTabCoordinator: CommunitiesTabCoordinator
    public  let settingsTabCoordinator: SettingsTabCoordinator
    
    public let feature: ChatFeature
    
    public init(feature: ChatFeature) {
        self.chatsTabCoordinator = ChatsTabCoordinator(feature: feature)
        self.updatesTabCoordinator = UpdatesTabCoordinator(feature: feature)
        self.callsTabCoordinator = CallsTabCoordinator(feature: feature)
        self.communitiesTabCoordinator = CommunitiesTabCoordinator(feature: feature)
        self.settingsTabCoordinator = SettingsTabCoordinator(feature: feature)
        self.feature = feature
        wireCrossFeatureHandlers()
    }

    private func wireCrossFeatureHandlers() {
        let forward: (NavigationIntent) -> Void = { [weak self] intent in
            self?.onCrossFeature?(intent)
        }
        chatsTabCoordinator.onCrossFeature = forward
        updatesTabCoordinator.onCrossFeature = forward
        callsTabCoordinator.onCrossFeature = forward
        communitiesTabCoordinator.onCrossFeature = forward
        settingsTabCoordinator.onCrossFeature = forward

        let exit: () -> Void = { [weak self] in
            self?.exitToMainApp()
        }
        chatsTabCoordinator.onExitToMainApp = exit
        settingsTabCoordinator.onExitToMainApp = exit

        let openConversation: (String) -> Void = { [weak self] conversationId in
            self?.openConversation(conversationId)
        }
        communitiesTabCoordinator.onOpenConversation = openConversation

        // Une opération lancée depuis le portefeuille est déjà faite et
        // annoncée : on ouvre son fil pour montrer le message, en attente ou
        // envoyé. Rien n'y est relancé.
        settingsTabCoordinator.onOpenFinanceConversation = { [weak self] type in
            guard let self else { return }
            self.selectedTab = .chats
            self.chatsTabCoordinator.popToRoot()
            Task { @MainActor [weak self] in
                let route = ChatsTabRoute.chatRoom(type: type, isArchived: false)
                self?.chatsTabCoordinator.push(route)
            }
        }
        updatesTabCoordinator.onOpenConversation = openConversation
    }

    /// Shows a conversation opened from another tab — a community group, a
    /// channel.
    ///
    /// The room lives in the chats tab and nowhere else: `ChatRoomScreen` is
    /// typed to that tab's coordinator. So the move is switch tab, then push.
    ///
    /// The push is a separate main-actor turn rather than the same one: the tab
    /// switch has to land first, otherwise the stack animates a push in a tab
    /// that is still on its way out. It is not queued as `pendingAction` because
    /// `ChatsTabView` never consumes one — its stack exists as soon as the
    /// TabView is built, so pushing straight into the path is what actually
    /// works.
    public func openConversation(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }

        let route = ChatsTabRoute.chatRoom(
            type: .group(conversationId: conversationId),
            isArchived: false
        )

        selectedTab = .chats
        chatsTabCoordinator.popToRoot()

        Task { @MainActor [weak self] in
            self?.chatsTabCoordinator.push(route)
        }
    }

    /// API d'avant le 2026-10-05, gardée pour les projets qui tirent le paquet.
    @available(*, deprecated, message: "Use apply(_:) with a ChatLaunchContext.")
    public func applyInitialRoute(_ route: ChatRoute) {
        apply(ChatLaunchContext(route: route, source: .tab))
    }

    /// La dernière ouverture appliquée — destination et provenance.
    public private(set) var lastLaunch: ChatLaunchContext?

    /// Ouvre le Chat sur ce que la Super App désigne.
    ///
    /// Les destinations financières ne portent qu'une référence, relue au
    /// serveur par la feuille qui la présente, quelle que soit la source.
    public func apply(_ launch: ChatLaunchContext) {
        lastLaunch = launch
        switch launch.route {
        case .chats:
            selectedTab = .chats
        case .updates:
            selectedTab = Tab.updates.landing(in: feature.enabledModules)
        case .communities:
            selectedTab = Tab.communities.landing(in: feature.enabledModules)
        case .calls:
            selectedTab = Tab.calls.landing(in: feature.enabledModules)
        case .settings:
            selectedTab = .settings
        case .share:
            // Handle share route - present contact selection for sharing
            selectedTab = .chats
            isPresentingShare = true

        case .conversation(let id):
            // `openConversation` existait déjà et n'avait pas d'appelant depuis
            // un lien profond : tout le chemin était en place sauf le dernier
            // maillon.
            openConversation(id)

        case .financialObject(let opaqueId, let objectType):
            selectedTab = .chats
            guard let reference = Self.financialObjectReference(opaqueId: opaqueId, objectType: objectType)
            else { return }
            presentedFinancialObject = PresentedFinancialObject(reference: reference)

        case .paymentLink(let token, let nonce):
            selectedTab = .chats
            presentedPaymentLink = PresentedPaymentLink(token: token, nonce: nonce)
            
        case .channel(let channelId):
            // Les canaux vivent dans l'onglet Actualités (`UpdatesTabRoute.channelRoom`).
            // Ces deux routes basculaient vers Communautés et s'arrêtaient là (B08).
            openChannel(channelId)

        case .channelInvite(let inviteCode):
            // Aperçu existant (`ChannelJoinPreviewSheet`) : le code est validé au
            // serveur avant toute adhésion.
            // Les canaux vivent dans l'onglet Actualités : sans lui, le lien est ignoré.
            guard Tab.updates.isEnabled(in: feature.enabledModules) else { return }
            selectedTab = .updates
            guard !inviteCode.isEmpty else { return }
            presentedChannelInvite = PresentedChannelInvite(inviteCode: inviteCode)
        }
    }
    

    /// Référence à relire pour un objet désigné par un push.
    ///
    /// `nil` si le type est inconnu : lire le mauvais type d'objet interrogerait
    /// le mauvais endpoint, on reste alors sur la liste. Aucune révision n'est
    /// connue — c'est le serveur qui la rendra.
    static func financialObjectReference(opaqueId: String, objectType: String) -> FinancialReference? {
        guard !opaqueId.isEmpty, let type = FinancialObjectType(rawValue: objectType) else { return nil }
        return FinancialReference(type: type, id: opaqueId, version: 0, correlationID: CorrelationId())
    }

    /// Montre un canal dans l'onglet Actualités — même geste qu'`openConversation`.
    private func openChannel(_ channelId: String) {
        guard Tab.updates.isEnabled(in: feature.enabledModules) else { return }
        selectedTab = .updates
        guard !channelId.isEmpty else { return }
        updatesTabCoordinator.popToRoot()
        Task { @MainActor [weak self] in
            self?.updatesTabCoordinator.push(UpdatesTabRoute.channelRoom(channelId: channelId))
        }
    }

    public func exitToMainApp() {
        onCrossFeature?(NavigationIntents.Wallet.home())
    }
    
   public func start() {
      
   }
    
    public func handleAuthSuccess() {
        isAuthenticated = true
    }
    
    public func handleShareContent(from url: URL) {
        debugLog("🔗 [ChatCoordinator] Handling share content (scheme: \(url.scheme ?? "nil"))")
        sharedContentUrl = url
        selectedTab = .chats
        isPresentingShare = true
        debugLog("🔗 [ChatCoordinator] Share content URL set, presenting share sheet...")
    }
    
    public func dismissShare() {
        debugLog("🔗 [ChatCoordinator] Dismissing share sheet...")
        isPresentingShare = false
        sharedContentUrl = nil
    }
    
    public func view() -> some View {
        ChatCoordinatorView(coordinator: self)
    }
}


/// Enveloppe identifiable pour `.sheet(item:)`.
struct PresentedPaymentLink: Identifiable, Equatable {
    let token: String
    let nonce: String
    var id: String { token }
}

struct PresentedChannelInvite: Identifiable, Equatable {
    let inviteCode: String
    var id: String { inviteCode }
}

struct PresentedFinancialObject: Identifiable, Equatable {
    let reference: FinancialReference
    var id: String { reference.identityKey }
}
