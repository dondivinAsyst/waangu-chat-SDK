//
//  CommunitiesTabView.swift
//  FeatureChat
//
//  Communities tab view following FeatureWallet ServicesTabView pattern
//

import SwiftUI
import WaanguNavigationKit


struct CommunitiesTabView: View {
    @Bindable var coordinator: CommunitiesTabCoordinator
    
    var body: some View {
        NavigationStack(path: $coordinator.navigationPath) {
            rootView
                .navigationDestination(for: CommunitiesTabRoute.self) { route in
                    destination(for: route)
                }
                .onAppear {
                    coordinator.consumePendingAction()
                }
        }
        .toolbar(
            coordinator.navigationPath.isEmpty ? .automatic : .hidden,
            for: .tabBar
        )
    }
    
    private var rootView: some View {
        coordinator.feature.makeCommunitiesView { route in
            coordinator.navigate(to: route)
        }
    }
    
    @ViewBuilder
    private func destination(for route: CommunitiesTabRoute) -> some View {
        CommunitiesDestinationView(
            route: route,
            coordinator: coordinator
        )
    }
}
