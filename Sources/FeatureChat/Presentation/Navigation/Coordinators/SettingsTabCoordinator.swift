//
//  SettingsTabCoordinator.swift
//  FeatureChat
//
//  Settings tab coordinator following FeatureWallet pattern
//

import SwiftUI
import WaanguCoreKit
import WaanguNavigationKit

@MainActor
@Observable
public final class SettingsTabCoordinator: TabStackCoordinator {
    
    public var navigationPath = NavigationPath()
    public var onCrossFeature: ((NavigationIntent) -> Void)?
    public var onExitToMainApp: (() -> Void)?
    public var pendingAction: (() -> Void)?
    
    public let feature: ChatFeature

    /// Ouvre le fil où une opération lancée depuis le portefeuille vient
    /// d'être annoncée — **après** l'opération, pour montrer son message.
    ///
    /// Branché par ``ChatFlowCoordinator`` : les Réglages n'ont pas la main sur
    /// l'onglet Discussions, et se l'arroger ferait d'un onglet le pilote d'un
    /// autre — ce que l'architecture du projet interdit.
    public var onOpenFinanceConversation: ((ConversationType) -> Void)?
    
    public init(feature: ChatFeature) {
        self.feature = feature
    }
    
    public func view() -> some View {
        SettingsTabView(coordinator: self)
    }
    
    public func start() { }
    
    public func navigate(to route: SettingsTabRoute) {
        push(route)
    }
}
