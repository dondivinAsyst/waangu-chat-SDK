//
//  SettingsDestinationView.swift
//  FeatureChat
//
//  Settings tab destination routing
//

import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct SettingsDestinationView: View {
    let route: SettingsTabRoute
    let coordinator: SettingsTabCoordinator
    
    var body: some View {
        switch route {
        case .root:
            EmptyView()
            
        case .profile:
            coordinator.feature.makeProfileView()

        case .privacy:
            EmptyView() // Placeholder for privacy settings view
            
        case .notifications:
            EmptyView() // Placeholder for notification settings view
            
        case .account:
            EmptyView() // Placeholder for account settings view

        case .finance:
            // Le portefeuille, et non le menu financier : hors conversation, la
            // question n'est pas « que faire avec cette personne ? » mais « où en
            // est mon compte ? ». Le menu complet reste atteignable par « Voir
            // tout », une fois le solde lu.
            WalletHomeView(
                surface: coordinator.feature.financeSurface,
                contacts: coordinator.feature.contactUseCases,
                discussions: coordinator.feature.discussionUseCases,
                publisher: coordinator.feature.publishFinanceMessage,
                translationService: coordinator.feature.translationService,
                onOpenConversation: { conversation in
                    coordinator.onOpenFinanceConversation?(conversation)
                },
                onBack: { coordinator.pop() },
                // Une seule conversation Copilot : celle de la liste des discussions.
                copilotStore: coordinator.feature.copilotConversationStore
            )

        case .myQRCode:
            MyQRCodeScreen(
                surface: coordinator.feature.financeSurface,
                userName: CurrentSessionInfo.shared.name,
                avatarURL: CurrentSessionInfo.shared.avatar,
                onOpenConversation: { conversation in
                    coordinator.onOpenFinanceConversation?(conversation)
                },
                onBack: { coordinator.pop() }
            )
        }
    }
}
