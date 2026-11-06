//
//  SettingsTabView.swift
//  FeatureChat
//
//  Settings tab view following FeatureWallet ServicesTabView pattern
//

import SwiftUI
import WaanguNavigationKit


struct SettingsTabView: View {
    @Bindable var coordinator: SettingsTabCoordinator
    
    var body: some View {
        NavigationStack(path: $coordinator.navigationPath) {
            rootView
                .navigationDestination(for: SettingsTabRoute.self) { route in
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
        coordinator.feature.makeSettingsView(
            onNavigate: { route in
                coordinator.navigate(to: route)
            },
            onExitToMainApp: coordinator.onExitToMainApp
        )
    }
    
    @ViewBuilder
    private func destination(for route: SettingsTabRoute) -> some View {
        SettingsDestinationView(
            route: route,
            coordinator: coordinator
        )
    }
}
