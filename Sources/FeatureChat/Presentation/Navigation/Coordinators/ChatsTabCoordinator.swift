//
//  ChatsTabCoordinator.swift
//  FeatureChat
//
//  Chats tab coordinator following FeatureWallet pattern
//

import SwiftUI
import WaanguNavigationKit

@MainActor
@Observable
public final class ChatsTabCoordinator: TabStackCoordinator {
    
    public var navigationPath = NavigationPath()
    public var onCrossFeature: ((NavigationIntent) -> Void)?
    public var onExitToMainApp: (() -> Void)?
    public var pendingAction: (() -> Void)?
    
    public let feature: ChatFeature

    /// Live chat room view models keyed by conversation id.
    /// Profile and group info screens reuse the same instance as the active chat room.
    private var chatRoomViewModelCache: [String: ChatRoomViewModel] = [:]
    
    public init(feature: ChatFeature) {
        self.feature = feature
        ChatAppearanceStore.shared.delegate = self
    }

    func chatRoomViewModel(
        for conversationId: String,
        make: () -> ChatRoomViewModel
    ) -> ChatRoomViewModel {
        if let cached = chatRoomViewModelCache[conversationId] {
            cached.syncChatAppearanceFromStore()
            return cached
        }
        let viewModel = make()
        chatRoomViewModelCache[conversationId] = viewModel
        return viewModel
    }

    func removeChatRoomViewModel(for conversationId: String) {
        chatRoomViewModelCache.removeValue(forKey: conversationId)
    }

    /// Drops every cached chat room view model. Call when tearing down the chat
    /// stack (header back → popToRoot) so stale receiver/messages can't leak
    /// into the next opened conversation.
    func clearChatRoomViewModelCache() {
        chatRoomViewModelCache.removeAll()
    }

    func syncCachedChatAppearances() {
        for viewModel in chatRoomViewModelCache.values {
            viewModel.syncChatAppearanceFromStore()
        }
    }
    
    public func view() -> some View {
        ChatsTabView(coordinator: self)
    }
    
    public func start() { }
    
    public func handle(_ route: ChatsTabRoute) {
        switch route {
        case .root: popToRoot()
        default: push(route)
        }
    }
}

extension ChatsTabCoordinator: ChatAppearanceStoreDelegate {
    func chatAppearanceDidChange() {
        syncCachedChatAppearances()
    }
}
