//
//  ChatsDestinationView.swift
//  FeatureChat
//
//  Chats tab destination routing
//

import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct ChatsDestinationView: View {
    let route: ChatsTabRoute
    let coordinator: ChatsTabCoordinator
    @Namespace private var imageTransitionNamespace
    
    var body: some View {
        switch route {
        case .root:
            EmptyView()
            
        case .chatRoom(let type, let isArchived):
            ChatRoomScreen(
                imageTransitionNamespace: imageTransitionNamespace,
                conversationType: type,
                chatListViewModel: coordinator.feature.makeChannelTabViewModel(),
                chatPartnerPickerViewModel: coordinator.feature.makeChatPartnerPickerViewModel(),
                phMediaManagerViewModel: coordinator.feature.phMediaManagerViewModel,
                messagesUseCases: coordinator.feature.messagesUseCases,
                discussionUseCases: coordinator.feature.discussionUseCases,
                // e2eeUseCases: coordinator.feature.e2eeUseCases, // Temporarily disabled
                pendingE2EEQueue: coordinator.feature.pendingE2EEQueue,
                contactsUseCases: coordinator.feature.contactUseCases,
                voiceRecordingViewModel: coordinator.feature.makeVoiceRecordingViewModel(),
                opusPlaybackService: coordinator.feature.opusPlaybackService,
                chatActionsUseCase: coordinator.feature.chatActionsUseCase,
                groupUseCases: coordinator.feature.groupUseCases,
                groupPermissionsUseCases: coordinator.feature.groupPermissionsUseCases,
                isArchived: isArchived,
                navigationCoord: coordinator,
                uploadViewModel: coordinator.feature.uploadViewModel,
                globalAudioManager: coordinator.feature.globalAudioManager,
                translationService: coordinator.feature.translationService,
                conversationRoomUseCases: coordinator.feature.conversationRoomUseCases,
                messagesStoreFactory: { coordinator.feature.makeChatRoomMessagesStore() },
                financeSurface: coordinator.feature.financeSurface
            )
            
        case .copilot:
            CopilotChatScreen(
                surface: coordinator.feature.financeSurface,
                store: coordinator.feature.copilotConversationStore,
                discussions: coordinator.feature.discussionUseCases,
                publisher: coordinator.feature.publishFinanceMessage
            )

        case .archiveChat:
            ArchiveChatList(
                viewModel: coordinator.feature.makeChannelTabViewModel(),
                navigationCoord: coordinator
            )
            .toolbar(.hidden, for: .tabBar)
            
        case let .profileView(contactId, discussionId, fallbackPhone, fallbackDisplayName,isBlocked):
            ContactProfileViewWrapper(
                imageTransitionNamespace: imageTransitionNamespace,
                contactId: contactId,
                discussionId: discussionId,
                feature: coordinator.feature,
                coordinator: coordinator,
                fallbackPhone: fallbackPhone,
                fallbackDisplayName: fallbackDisplayName,
                isBlocked:isBlocked
            )
            
        case let .groupInfoView(discussionId, groupName):
            if #available(iOS 17.0, *) {
                GroupInfoViewWrapper(
                    discussionId: discussionId,
                    groupName: groupName,
                    feature: coordinator.feature,
                    coordinator: coordinator
                )
                .toolbar(.hidden, for: .navigationBar)
            } else {
                EmptyView()
            }
            
        case let .groupPermissions(discussionId, groupName):
            if #available(iOS 17.0, *) {
                GroupPermissionsViewWrapper(
                    discussionId: discussionId,
                    groupName: groupName,
                    feature: coordinator.feature,
                    coordinator: coordinator
                )
                .toolbar(.hidden, for: .navigationBar)
            } else {
                EmptyView()
            }

        case let .pendingJoinRequests(discussionId, groupName):
            if #available(iOS 17.0, *) {
                GroupPendingJoinRequestsViewWrapper(
                    discussionId: discussionId,
                    groupName: groupName,
                    feature: coordinator.feature,
                    coordinator: coordinator
                )
                .toolbar(.hidden, for: .navigationBar)
            } else {
                EmptyView()
            }
        }
    }
}

// Wrapper views reuse the coordinator's cached ChatRoomViewModel when available.
@available(iOS 16.0, *)
private struct ContactProfileViewWrapper: View {
    let imageTransitionNamespace: Namespace.ID
    let contactId: String
    let discussionId: String
    let feature: ChatFeature
    let coordinator: ChatsTabCoordinator
    let fallbackPhone: String?
    let fallbackDisplayName: String?
    let isBlocked: Bool
    
    var body: some View {
        ContactProfileView(
            imageTransitionNamespace: imageTransitionNamespace,
            contactId: contactId,
            discussionId: discussionId,
            chatPickerVM: feature.makeChatPartnerPickerViewModel(),
            discussionUseCases: feature.discussionUseCases,
            messagesUseCases: feature.messagesUseCases,
            contactsUseCases: feature.contactUseCases,
            chatRoomVM: coordinator.chatRoomViewModel(for: discussionId, make: makeChatRoomViewModel),
            fallbackPhone: fallbackPhone,
            fallbackDisplayName: fallbackDisplayName,
            uploadVM: feature.uploadViewModel,
            navigationCoord: coordinator
        )
    }

    private func makeChatRoomViewModel() -> ChatRoomViewModel {
        let userRoom = UserRoom(
            idContact: contactId,
            userId: "",
            phone: fallbackPhone,
            name: fallbackDisplayName,
            avatar: nil,
            description: nil,
            onlineStatus: UserOnline(
                status: .offline,
                lastSeen: "Never",
                userId: ""
            ),
            isBlocked: isBlocked
        )

        return ChatRoomViewModel(
            userRoom,
            isGroup: false,
            conversationId: discussionId,
            messagesUseCase: feature.messagesUseCases,
            discussionsUseCase: feature.discussionUseCases,
            pendingE2EEQueue: feature.pendingE2EEQueue,
            voiceRecordingViewModel: feature.makeVoiceRecordingViewModel(),
            contactsUseCases: feature.contactUseCases,
            chatActionsUseCase: feature.chatActionsUseCase,
            translationService: feature.translationService,
            messagesStore: feature.makeChatRoomMessagesStore(),
            conversationRoomUseCases: feature.conversationRoomUseCases,
            financeSurface: feature.financeSurface
        )
    }
}

@available(iOS 17.0, *)
private struct GroupInfoViewWrapper: View {
    let discussionId: String
    let groupName: String
    let feature: ChatFeature
    let coordinator: ChatsTabCoordinator
    
    var body: some View {
        GroupInfoView(
            discussionId: discussionId,
            groupName: groupName,
            chatRoomVM: coordinator.chatRoomViewModel(for: discussionId, make: makeChatRoomViewModel),
            discussionUseCases: feature.discussionUseCases,
            groupUseCases: feature.groupUseCases,
            groupPermissionsUseCases: feature.groupPermissionsUseCases,
            contactUseCase: feature.contactUseCases,
            navigationCoord: coordinator,
            fileUploadUseCases: feature.fileUplaodUseCases
        )
    }

    private func makeChatRoomViewModel() -> ChatRoomViewModel {
        let userRoom = UserRoom(
            idContact: discussionId,
            userId: "",
            phone: nil,
            name: groupName,
            avatar: nil,
            description: nil,
            onlineStatus: UserOnline(
                status: .offline,
                lastSeen: "Never",
                userId: ""
            ),
            isBlocked: false
        )

        return ChatRoomViewModel(
            userRoom,
            isGroup: true,
            conversationId: discussionId,
            messagesUseCase: feature.messagesUseCases,
            discussionsUseCase: feature.discussionUseCases,
            pendingE2EEQueue: feature.pendingE2EEQueue,
            voiceRecordingViewModel: feature.makeVoiceRecordingViewModel(),
            contactsUseCases: feature.contactUseCases,
            chatActionsUseCase: feature.chatActionsUseCase,
            groupUseCases: feature.groupUseCases,
            groupPermissionsUseCases: feature.groupPermissionsUseCases,
            translationService: feature.translationService,
            messagesStore: feature.makeChatRoomMessagesStore(),
            conversationRoomUseCases: feature.conversationRoomUseCases,
            financeSurface: feature.financeSurface
        )
    }
}

@available(iOS 17.0, *)
private struct GroupPendingJoinRequestsViewWrapper: View {
    let discussionId: String
    let groupName: String
    let feature: ChatFeature
    let coordinator: ChatsTabCoordinator

    @StateObject private var viewModel: GroupPendingJoinRequestsViewModel

    init(
        discussionId: String,
        groupName: String,
        feature: ChatFeature,
        coordinator: ChatsTabCoordinator
    ) {
        self.discussionId = discussionId
        self.groupName = groupName
        self.feature = feature
        self.coordinator = coordinator
        _viewModel = StateObject(
            wrappedValue: GroupPendingJoinRequestsViewModel(
                discussionId: discussionId,
                groupName: groupName,
                groupUseCases: feature.groupUseCases
            )
        )
    }

    var body: some View {
        GroupPendingJoinRequestsView(
            viewModel: viewModel,
            navigationCoord: coordinator,
            translationService: feature.translationService
        )
    }
}

@available(iOS 17.0, *)
private struct GroupPermissionsViewWrapper: View {
    let discussionId: String
    let groupName: String
    let feature: ChatFeature
    let coordinator: ChatsTabCoordinator
    @State private var group: GroupChat
    @State private var isRefreshingGroup = true

    init(
        discussionId: String,
        groupName: String,
        feature: ChatFeature,
        coordinator: ChatsTabCoordinator
    ) {
        self.discussionId = discussionId
        self.groupName = groupName
        self.feature = feature
        self.coordinator = coordinator
        // Creator unknown until the stored group loads — see `GroupInfoViewModel`.
        // Claiming it here handed the permissions screen to whoever opened it.
        _group = State(
            initialValue: GroupChat(
                localId: discussionId,
                name: groupName,
                createdBy: ""
            )
        )
    }

    var body: some View {
        ZStack {
            GroupPermissionsView(
                group: group,
                permissionsUseCases: feature.groupPermissionsUseCases,
                navigationCoord: coordinator,
                translationService: feature.translationService
            )
            .id(group.permissionsViewStateToken)

            if isRefreshingGroup {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()
                ProgressView()
            }
        }
        .task {
            isRefreshingGroup = true
            defer { isRefreshingGroup = false }
            if let loaded = try? await feature.groupUseCases.getGroup.execute(groupId: discussionId) {
                group = loaded
            }
        }
    }
}
