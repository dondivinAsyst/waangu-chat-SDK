//
//  UpdatesDestinationView.swift
//  FeatureChat
//
//  Updates/Stories tab destination routing
//

import SwiftUI

@available(iOS 16.0, *)
struct UpdatesDestinationView: View {
    let route: UpdatesTabRoute
    let coordinator: UpdatesTabCoordinator
    
    var body: some View {
        switch route {
        case .root:
            EmptyView()
            
        case .storieView(let storyId):
            StatusViewer(
                storyId: storyId,
                viewModel: coordinator.feature.makeStoriesViewModel(),
                updateTabCoordinator: coordinator,
                translationService: coordinator.feature.translationService
            )
            .navigationBarBackButtonHidden()
            
        case .myStoriesView:
            MyStatusView(
                navigationCoord: coordinator,
                statusStore: coordinator.feature.makeStoriesViewModel(),
                viewModel: coordinator.feature.phMediaManagerViewModel,
                translationService: coordinator.feature.translationService
            )
                .navigationBarBackButtonHidden()
            
        case .createStoryView:
            EmptyView() // Placeholder for create story view
            
        case .editTabStoryView(let initialTab):
            EditorTabView(
                initialTab: initialTab,
                statusStore: coordinator.feature.makeStoriesViewModel(),
                translationService: coordinator.feature.translationService
            )
                .environmentObject(coordinator.feature.makeStoriesViewModel())
                .navigationBarBackButtonHidden()
            
        case .camera:
            CameraView()
                .navigationBarBackButtonHidden()
            
        case .channelRoom(let channelId):
            ChannelRoomView(
                viewModel: coordinator.feature.makeChannelRoomViewModel(channelId: channelId),
                mediaViewModel: coordinator.feature.phMediaManagerViewModel,
                galleryViewModel: coordinator.feature.makeChannelGalleryViewModel(channelId: channelId),
                financeSurface: coordinator.feature.financeSurface,
                statusStore: coordinator.feature.makeStoriesViewModel(),
                contactsUseCases: coordinator.feature.contactUseCases,
                discussionUseCases: coordinator.feature.discussionUseCases,
                makeSearchViewModel: { coordinator.feature.makeMessageSearchViewModel() },
                onShowInfo: { id in
                    coordinator.navigate(to: .channelDetail(channelId: id))
                },
                onShareToStatus: {
                    coordinator.navigate(to: .editTabStoryView(initialTab: .text))
                },
                onUnfollowed: { coordinator.pop() }
            )

        case .channelDetail(let channelId):
            ChannelDetailView(
                viewModel: coordinator.feature.makeChannelRoomViewModel(channelId: channelId),
                contactsUseCases: coordinator.feature.contactUseCases,
                onUnfollowed: { coordinator.popToRoot() }
            )

        case .exploreChannels:
            ExploreChannelsView(
                viewModel: coordinator.feature.makeChannelsViewModel(),
                onOpenChannel: { channelId in
                    coordinator.navigate(to: .channelRoom(channelId: channelId))
                }
            )

        case .statusEditorView(let selectedMedia):
            StatusEditor(
                selectedMedia: selectedMedia,
                statusStore: coordinator.feature.makeStoriesViewModel(),
                phMediaManagerViewModel: coordinator.feature.phMediaManagerViewModel,
                translationService: coordinator.feature.translationService
            )
           
            .navigationBarBackButtonHidden()
        }
    }
}
