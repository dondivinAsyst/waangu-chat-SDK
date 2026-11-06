//
//  ChatsTabView.swift
//  FeatureChat
//
//  Chats tab view following FeatureWallet HomeTabView pattern
//

import SwiftUI
import WaanguNavigationKit


struct ChatsTabView: View {
    @Bindable var coordinator: ChatsTabCoordinator
    
    var body: some View {
    
        NavigationStack(path: $coordinator.navigationPath) {
            coordinator.feature.makeChatsListView(
                coordinator: coordinator
            )
            .navigationDestination(for: ChatsTabRoute.self) { route in
                ChatsDestinationView(
                    route: route,
                    coordinator: coordinator
                )
            }
        }
    }
}
