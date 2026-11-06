//
//  UpdatesTabView.swift
//  FeatureChat
//
//  Updates/Stories tab view following FeatureWallet ServicesTabView pattern
//

import SwiftUI
import WaanguNavigationKit


struct UpdatesTabView: View {
    @Bindable var coordinator: UpdatesTabCoordinator
    
    var body: some View {
        NavigationStack(path: $coordinator.navigationPath) {
            rootView
                .navigationDestination(for: UpdatesTabRoute.self) { route in
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
        coordinator.feature.makeUpdatesView(onNavigate:{ route in
            coordinator.navigate(to: route)
        } ,coordinator: coordinator)
    }
    
    @ViewBuilder
    private func destination(for route: UpdatesTabRoute) -> some View {
        UpdatesDestinationView(
            route: route,
            coordinator: coordinator
        )
    }
}

