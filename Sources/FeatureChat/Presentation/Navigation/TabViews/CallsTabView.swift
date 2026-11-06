//
//  CallsTabView.swift
//  FeatureChat
//
//  Calls tab view following FeatureWallet ServicesTabView pattern
//

import SwiftUI
import WaanguNavigationKit


struct CallsTabView: View {
    @Bindable var coordinator: CallsTabCoordinator
    
    var body: some View {
        NavigationStack(path: $coordinator.navigationPath) {
            rootView
                .navigationDestination(for: CallsTabRoute.self) { route in
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
        coordinator.feature.makeCallsView { route in
            coordinator.navigate(to: route)
        }
    }
    
    @ViewBuilder
    private func destination(for route: CallsTabRoute) -> some View {
        CallsDestinationView(
            route: route,
            coordinator: coordinator
        )
    }
}
