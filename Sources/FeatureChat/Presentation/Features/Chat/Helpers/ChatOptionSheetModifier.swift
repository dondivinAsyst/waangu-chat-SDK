//
//  chatListModifiers.swift
//  Pods
//
//  Created by Asyst on 10/8/25.
//


import SwiftUI

struct ChatOptionSheetModifier: ViewModifier {
    var isArchived:Bool
    @Binding var showSheetOption: Bool
    @Binding var isConfirmDelete: Bool
    var selectedDiscussion: DiscussionChatItem?
    var viewModel: ChannelTabViewModel
    
    @State private var dynamicHeight: CGFloat = 200

    func body(content: Content) -> some View {
        content
            .chatAppearanceSheet(isPresented: $showSheetOption) {
                if #available(iOS 16.4, *) {
                    ChatOptionSheet(
                        isArchived:isArchived,
                        contactName: selectedDiscussion?.contact?.userName ?? "",
                        contactImage: selectedDiscussion?.contact?.image ?? "",
                        isGroup: selectedDiscussion?.contact?.isGroup ?? false,
                        hasLeftGroup: selectedDiscussion.map { viewModel.hasLeftGroupDiscussion($0) } ?? false,
                        isConfirmDelete: isConfirmDelete,
                        isBlocked: selectedDiscussion?.contact?.isBlocked ?? false,
                        viewModel: viewModel,
                        conversationId: selectedDiscussion?.conversationId ?? "",
                        translationService: viewModel.translationService,
                        onDismiss: {
                            showSheetOption = false
                            isConfirmDelete = false
                        },
                        onPressAction: { action in
//                            if action == .delete {
//                                showSheetOption = false
//                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
//                                    isConfirmDelete = true
//                                    showSheetOption = true
//                                }
//                                return
//                            }

                            if let chat = selectedDiscussion {
                                viewModel.onPressAction(action: action, chat: chat)
                            }
                        },
                        dynamicHeight: $dynamicHeight
                    )
                    .presentationDetents([.height(dynamicHeight)])
                    .presentationBackground(Color(.systemGray6))
                }
            }
    }
}

extension View {
    func chatOptionSheet(
        isArchived: Bool = false,
        showSheetOption: Binding<Bool>,
        isConfirmDelete: Binding<Bool>,
        selectedDiscussion: DiscussionChatItem?,
        viewModel: ChannelTabViewModel
    ) -> some View {
        modifier(ChatOptionSheetModifier(
            isArchived:isArchived,
            showSheetOption: showSheetOption,
            isConfirmDelete: isConfirmDelete,
            selectedDiscussion: selectedDiscussion,
            viewModel: viewModel
        ))
    }
}
