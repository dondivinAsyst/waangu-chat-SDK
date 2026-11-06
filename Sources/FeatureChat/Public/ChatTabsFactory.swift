//
//  ChatTabsFactory.swift
//  FeatureChat
//
//  Public factory for creating chat tab views
//  Following FeatureWallet/Public/WalletTabsFactory.swift pattern
//

import SwiftUI
import WaanguNavigationKit
import WaanguCoreKit

@available(iOS 16.0, *)
struct ChatTabsFactory {
    
    static func makeChatsTab(
        coordinator: ChatsTabCoordinator
    ) -> some View {
        ChatTabCoordinatorView(coordinator: coordinator)
    }
    
    static func makeUpdatesTab(
        coordinator: UpdatesTabCoordinator
    ) -> some View {
        UpdatesTabCoordinatorView(coordinator: coordinator)
    }
    
    static func makeCallsTab(
        coordinator: CallsTabCoordinator
    ) -> some View {
        CallsTabCoordinatorView(coordinator: coordinator)
    }
    
    static func makeCommunitiesTab(
        coordinator: CommunitiesTabCoordinator
    ) -> some View {
        CommunitiesTabCoordinatorView(coordinator: coordinator)
    }
    
    static func makeSettingsTab(
        coordinator: SettingsTabCoordinator
    ) -> some View {
        SettingsTabCoordinatorView(coordinator: coordinator)
    }
    
    static func makeShareContentView(
        url: URL,
        shareProcessor: any ShareContentProcessorProtocol,
        translationService: (any TranslationServiceProtocol)? = nil
    ) -> some View {
        ShareContentView(
            url: url,
            shareProcessor: shareProcessor,
            translationService: translationService
        )
    }
}

// MARK: - Coordinator Wrapper Views

@available(iOS 16.0, *)
struct ChatTabCoordinatorView: View {
    let coordinator: ChatsTabCoordinator
    
    var body: some View {
        CoordinatorView(coordinator: coordinator)
            .onAppear { coordinator.start() }
    }
}

@available(iOS 16.0, *)
struct UpdatesTabCoordinatorView: View {
    let coordinator: UpdatesTabCoordinator
    
    var body: some View {
        CoordinatorView(coordinator: coordinator)
            .onAppear { coordinator.start() }
    }
}

@available(iOS 16.0, *)
struct CallsTabCoordinatorView: View {
    let coordinator: CallsTabCoordinator
    
    var body: some View {
        CoordinatorView(coordinator: coordinator)
            .onAppear { coordinator.start() }
    }
}

@available(iOS 16.0, *)
struct CommunitiesTabCoordinatorView: View {
    let coordinator: CommunitiesTabCoordinator
    
    var body: some View {
        CoordinatorView(coordinator: coordinator)
            .onAppear { coordinator.start() }
    }
}

@available(iOS 16.0, *)
struct SettingsTabCoordinatorView: View {
    let coordinator: SettingsTabCoordinator
    
    var body: some View {
        CoordinatorView(coordinator: coordinator)
            .onAppear { coordinator.start() }
    }
}
