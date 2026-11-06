//
//  CommunitiesTabCoordinator.swift
//  FeatureChat
//
//  Communities tab coordinator following FeatureWallet pattern
//

import SwiftUI
import WaanguNavigationKit

@MainActor
@Observable
public final class CommunitiesTabCoordinator: TabStackCoordinator {
    
    public var navigationPath = NavigationPath()
    public var onCrossFeature: ((NavigationIntent) -> Void)?
    public var pendingAction: (() -> Void)?
    
    public let feature: ChatFeature
    
    public init(feature: ChatFeature) {
        self.feature = feature
    }
    
    public func view() -> some View {
        CommunitiesTabView(coordinator: self)
    }
    
    public func start() { }
    
    public func navigate(to route: CommunitiesTabRoute) {
        push(route)
    }

    /// Opens a conversation that belongs to another tab.
    ///
    /// The chat room is owned by the chats tab — its screen is typed to that
    /// tab's coordinator — so this hands the request up to `ChatCoordinator`,
    /// which switches tabs and pushes the room there. Unset in a configuration
    /// that has no chats tab, in which case tapping a group simply does nothing
    /// rather than pushing a room into the wrong stack.
    public var onOpenConversation: ((String) -> Void)?

    public func openConversation(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        onOpenConversation?(conversationId)
    }

}
