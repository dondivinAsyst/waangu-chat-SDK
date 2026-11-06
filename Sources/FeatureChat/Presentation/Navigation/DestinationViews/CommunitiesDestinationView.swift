//
//  CommunitiesDestinationView.swift
//  FeatureChat
//
//  Communities tab destination routing
//

import SwiftUI

@available(iOS 16.0, *)
struct CommunitiesDestinationView: View {

    let route: CommunitiesTabRoute
    let coordinator: CommunitiesTabCoordinator

    var body: some View {
        switch route {
        case .root:
            EmptyView()

        case .communityDetail(let communityId):
            CommunityDetailView(
                viewModel: coordinator.feature.makeCommunityDetailViewModel(communityId: communityId),
                partnerPicker: coordinator.feature.makeChatPartnerPickerViewModel(),
                onOpenConversation: { conversationId in
                    coordinator.openConversation(conversationId)
                },
                onShowInfo: { id in
                    coordinator.navigate(to: .communityInfo(communityId: id))
                },
                onLeft: {
                    coordinator.popToRoot()
                }
            )

        case .communityInfo(let communityId):
            CommunityInfoView(
                viewModel: coordinator.feature.makeCommunityDetailViewModel(communityId: communityId),
                onShowMembers: { id in
                    coordinator.navigate(to: .communityMembers(communityId: id))
                },
                onShowSettings: { id in
                    coordinator.navigate(to: .communitySettings(communityId: id))
                },
                onLeft: {
                    coordinator.popToRoot()
                }
            )

        case .communitySettings(let communityId):
            CommunitySettingsView(
                viewModel: coordinator.feature.makeCommunitySettingsViewModel(communityId: communityId)
            )

        case .communityMembers(let communityId):
            CommunityMembersView(
                viewModel: coordinator.feature.makeCommunityDetailViewModel(communityId: communityId)
            )

        case .joinCommunity:
            JoinCommunityView(
                viewModel: coordinator.feature.makeCommunitiesViewModel(),
                onJoined: { coordinator.pop() },
                onCancel: { coordinator.pop() }
            )
        }
    }
}
