//
//  ChatOptionSheet.swift
//  Pods
//
//  Created by Asyst on 10/6/25.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit


struct ChatOptionSheet: View {
    var isArchived: Bool
    var contactName: String
    var contactImage: String
    var isGroup: Bool
    var hasLeftGroup: Bool
    var isConfirmDelete: Bool
    var isBlocked: Bool
    var viewModel: ChannelTabViewModel?
    var conversationId: String = ""
    let translationService: (any TranslationServiceProtocol)?
    var onDismiss: () -> Void
    let onPressAction: (DiscussionActionType) -> Void
    @Binding var dynamicHeight: CGFloat
    @State private var showListPicker = false

    init(
        isArchived: Bool,
        contactName: String,
        contactImage: String,
        isGroup: Bool,
        hasLeftGroup: Bool,
        isConfirmDelete: Bool,
        isBlocked: Bool,
        viewModel: ChannelTabViewModel? = nil,
        conversationId: String = "",
        translationService: (any TranslationServiceProtocol)? = nil,
        onDismiss: @escaping () -> Void,
        onPressAction: @escaping (DiscussionActionType) -> Void,
        dynamicHeight: Binding<CGFloat>
    ) {
        self.isArchived = isArchived
        self.contactName = contactName
        self.contactImage = contactImage
        self.isGroup = isGroup
        self.hasLeftGroup = hasLeftGroup
        self.isConfirmDelete = isConfirmDelete
        self.isBlocked = isBlocked
        self.viewModel = viewModel
        self.conversationId = conversationId
        self.translationService = translationService
        self.onDismiss = onDismiss
        self.onPressAction = onPressAction
        self._dynamicHeight = dynamicHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 12) {
               
                if !isConfirmDelete {
                    CircularProfileImageView(contactImage, size: .xSmall)
                        .foregroundColor(.black.opacity(0.5))
                }

                Text(
                    isConfirmDelete
                        ? t(ChatTranslationKeys.CHAT_MORE_DELETE_CHAT_CONFIRM, args: [contactName])
                        : contactName
                )
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        
                }
            }
            .padding(.horizontal)
          
            // MARK: - Content
                Group {
                 if !isConfirmDelete {
                     normalContent(onDismiss: onDismiss)
                 } else {
                     confirmDeleteContent(onDismiss: onDismiss)
                 }
             }
      
            .padding()
            .background(GeometryReader { proxy in
                Color.clear.onAppear {
                    DispatchQueue.main.async {
                        dynamicHeight = proxy.size.height + 70
                    }
                }
            })
        }
        .background(Color(.systemGray6))
        .onAppear {
            viewModel?.reloadCustomDiscussionLists()
        }
        .chatAppearanceSheet(isPresented: $showListPicker) {
            if let viewModel, !conversationId.isEmpty {
                DiscussionListPickerSheet(
                    viewModel: viewModel,
                    conversationId: conversationId,
                    onDismiss: { showListPicker = false }
                )
            }
        }
    }
        
        private func normalContent(onDismiss: @escaping () -> Void) -> some View {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        OptionRow(title: t(ChatTranslationKeys.CHAT_MORE_MUTE), icon: "speaker.slash.fill") {
                            onPressAction(.toggleMute)
                            onDismiss()
                        }
                        OptionRow(title: t(ChatTranslationKeys.CHAT_MORE_FAVORITE), icon: "star.fill") {
                            onPressAction(.toggleFavorite)
                            onDismiss()
                        }
                        OptionRow(title: t(ChatTranslationKeys.DISCUSSION_LIST_ADD_TO_LIST), icon: "folder.badge.plus") {
                            showListPicker = true
                        }
                        OptionRow(
                            title: isGroup
                                ? t(ChatTranslationKeys.GROUP_INFO_TITLE)
                                : t(ChatTranslationKeys.CONTACT_INFO_TITLE),
                            icon: "info.circle"
                        ) {
                            onPressAction(.showContactInfo)
                            onDismiss()
                        }
                        OptionRow(
                            title: isGroup && hasLeftGroup
                                ? t(ChatTranslationKeys.CHAT_MORE_DELETE_CHAT)
                                : t(ChatTranslationKeys.CHAT_MORE_CLEAR_CHAT),
                            icon: isGroup && hasLeftGroup ? "trash.fill" : "xmark.circle",
                            color: isGroup && hasLeftGroup ? .red : .primary,
                            showDivider: false
                        ) {
                            if isGroup && hasLeftGroup {
                                onPressAction(.delete)
                            } else {
                                onPressAction(.clearChat)
                            }
                            onDismiss()
                        }
                       
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Spacer().frame(height: 12)

                    VStack(spacing: 0) {
                        if isGroup {
                            if hasLeftGroup {
                                OptionRow(
                                    title: t(ChatTranslationKeys.CHAT_MORE_DELETE_CHAT),
                                    icon: "trash.fill",
                                    color: .red,
                                    showDivider: false
                                ) {
                                    onPressAction(.delete)
                                    onDismiss()
                                }
                            } else {
                                OptionRow(
                                    title: t(ChatTranslationKeys.GROUP_INFO_EXIT_GROUP),
                                    icon: "rectangle.portrait.and.arrow.right",
                                    color: .red,
                                    showDivider: false
                                ) {
                                    onPressAction(.exitGroup)
                                    onDismiss()
                                }
                            }
                        } else {
                            OptionRow(
                                title: isBlocked
                                    ? t(ChatTranslationKeys.CHAT_MORE_UNBLOCK_USER, args: [contactName])
                                    : t(ChatTranslationKeys.CHAT_MORE_BLOCK_USER_NAMED, args: [contactName]),
                                icon: isBlocked ? "checkmark.circle" : "nosign",
                                color: .red
                            ) {
                                onPressAction(.toggleBlock)
                                onDismiss()
                            }
                            OptionRow(
                                title: t(ChatTranslationKeys.CHAT_MORE_DELETE_CHAT),
                                icon: "trash.fill",
                                color: .red,
                                showDivider: false
                            ) {
                                onPressAction(.delete)
                                onDismiss()
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            // MARK: - Confirm Delete Content
            private func confirmDeleteContent(onDismiss: @escaping () -> Void) -> some View {
                VStack(spacing: 0) {
                    OptionRow(title: common("delete"), icon: "trash.fill", color: .red) {
                        onPressAction(.delete)
                        onDismiss()
                    }
                    if !isArchived {
                        OptionRow(
                            title: t(ChatTranslationKeys.CHAT_MORE_ARCHIVE_INSTEAD),
                            icon: "archivebox",
                            showDivider: false
                        ) {
                            onPressAction(.toggleArchive(true))
                            onDismiss()
                        }
                    }
                   
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - OptionRow Component
struct OptionRow: View {
    var title: String
    var icon: String
    var color: Color = .primary
    var showDivider: Bool = true
    let onSelect: () -> Void
    var body: some View {
        
        VStack(spacing:0) {
            HStack {
                Text(title)
                    .foregroundColor(color)

                Spacer()

                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 22))
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
            
            if showDivider {
                Divider()
                    .padding(.leading)
                    .frame(height: 0.3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
