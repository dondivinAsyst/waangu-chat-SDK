//
//  ArchiveChatList.swift
//  Pods
//
//  Created by Asyst on 10/7/25.
//
import SwiftUI
import WaanguSharedUI


@available(iOS 16.0, *)
struct ArchiveChatList: View {
    @ObservedObject var viewModel: ChannelTabViewModel
    let navigationCoord: ChatsTabCoordinator
    
    @State private var showSheetOption: Bool = false
    @State private var selectedDiscussion:DiscussionChatItem? = nil
    @State private var isConfirmDelete: Bool = false

    var body: some View {
        
        List {
            ForEach(viewModel.archivedDiscussions, id: \.id) { item in
                DiscussionChat(
                    isArchived: true,
                    discussion: item,
                    hasLeftGroup: viewModel.hasLeftGroupDiscussion(item),
                    isGroupCreatedByCurrentUser: viewModel.isGroupCreatedByCurrentUser(item),
                    typingUser: nil,
                    onShowMoreAction: {
                        selectedDiscussion = item
                        showSheetOption = true
                    }, onPressAction: { action in
                        viewModel.onPressAction(action: action, chat: item)
                    },
                    navigationCoord: navigationCoord,
                    translator: viewModel.translationService
                )
                .onTapGesture {
                    // ✅ Check if this is a group discussion
                    let conversationType: ConversationType
                    if item.contact?.isGroup == true {
                        conversationType = .group(conversationId: item.conversationId)
                    } else {
                        conversationType = .direct(
                            phoneNumber: item.contact?.phone ?? "",
                            conversationId: item.conversationId
                        )
                    }
                    
                    let route: ChatsTabRoute = .chatRoom(type: conversationType, isArchived: true)
                    navigationCoord.push(route)
                }

            }
        }
        .chatOptionSheet(
            isArchived: true,
            showSheetOption: $showSheetOption,
            isConfirmDelete: $isConfirmDelete,
            selectedDiscussion: selectedDiscussion,
            viewModel: viewModel
        )
        .onChange(of: viewModel.archivedDiscussions) { newValue in
            if newValue.count == 0 {
//                viewModel.navRoutes.removeLast()
                navigationCoord.pop()
            }
        }
        .onChange(of: showSheetOption) { newValue in
            if !newValue {
                isConfirmDelete = false
            }
        }
        .discussionDeletionDialog(
            context: $viewModel.deletionDialog,
            translationService: viewModel.translationService,
            onPrimary: { viewModel.confirmDeletionPrimaryAction() },
            onDeleteLocalContent: { viewModel.confirmDeleteLocalContent() },
            onLeaveGroup: { viewModel.confirmLeaveGroupFromDialog() },
            onExitKeepLocally: { viewModel.confirmExitAndKeepLocally() },
            onExitDeleteLocally: { viewModel.confirmExitAndDeleteLocally() }
        )
        .postLeaveLocalCleanupDialog(
            context: $viewModel.postLeaveCleanupDialog,
            translationService: viewModel.translationService,
            onKeepLocally: { viewModel.confirmPostLeaveKeepLocally() },
            onDeleteLocally: { viewModel.confirmPostLeaveDeleteLocally() }
        )
        .alert(
            viewModel.translationService?.resolve(key: ChatTranslationKeys.CHAT_LIST_DELETION_FAILED, module: ChatTranslationKeys.MODULE).value ?? "Deletion Failed",
            isPresented: Binding(
                get: { viewModel.deletionErrorMessage != nil },
                set: { if !$0 { viewModel.deletionErrorMessage = nil } }
            )
        ) {
            Button(viewModel.translationService?.resolve(key: "ok", module: ChatTranslationKeys.COMMON_MODULE).value ?? "OK", role: .cancel) {
                viewModel.deletionErrorMessage = nil
            }
        } message: {
            if let message = viewModel.deletionErrorMessage {
                Text(message)
            }
        }
        .discussionActionLoadingOverlay(
            isLoading: viewModel.isActionLoading,
            message: viewModel.actionLoadingMessage
        )
        .discussionListToast(message: viewModel.discussionListToastMessage)
        .edgesIgnoringSafeArea(.bottom)
        .listStyle(.plain)
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            
            ToolbarItemGroup(placement: .topBarLeading) {
                HStack(spacing:0) {
                    Button {
//                        viewModel.navRoutes.removeLast()
                        navigationCoord.pop()
                    }
                    label: {
                        Image(systemName: "chevron.backward")
                            .foregroundColor(.primary)
                            .font(.headline.weight(.bold))
                    }
                    
                    Text("\(viewModel.archivedDiscussions.count)")
                }
               
                
            }
                
            ToolbarItem(placement: .principal) {
                Text(viewModel.translationService?.resolve(key: ChatTranslationKeys.ARCHIVED_LABEL, module: ChatTranslationKeys.MODULE).value ?? "Archived")
                    .font(.headline)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
            
                Button(viewModel.translationService?.resolve(key: ChatTranslationKeys.ARCHIVE_EDIT, module: ChatTranslationKeys.MODULE).value ?? "Edit"){
                    
                }
            }
        }

           
    }
}
