//
//  ChatPartnerPickerScreen.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 12.01.2025.
//

import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct ChatPartnerPickerScreen: View {
    
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel : ChatPartnerPickerViewModel
    let translationService: (any TranslationServiceProtocol)?
    var onCreate: (_ newChannel: ChannelItem) -> Void
    var onCreateGroup: (_ groupName: String, _ members: [UserContactProps], _ image: UIImage?, _ settings: GroupSettings) -> Void
    let navigationCoord: ChatsTabCoordinator
    
    
    var body: some View {
        if #available(iOS 16.0, *) {
            mainNavigationStack
        } else {
            // Fallback on earlier versions
            Text(t(ChatTranslationKeys.NEW_CHAT_IOS_REQUIRED))
        }
    }
    
    @ViewBuilder
    private var mainNavigationStack: some View {
        NavigationStack(path: $viewModel.navStack) {
            mainListView
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: t(ChatTranslationKeys.NEW_CHAT_SEARCH_PLACEHOLDER))
                .onChange(of: searchText) { _ in
                    viewModel.searchContacts(searchText)
                }
                .navigationTitle(t(ChatTranslationKeys.NEW_CHAT_TITLE))
                .navigationDestination(for: ChannelCreationRoute.self) { route in
                    destinationView(for: route)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    trailingNavItem()
                }
                .onAppear {
                    handleOnAppear()
                }
        }
    }
    
    @ViewBuilder
    private var mainListView: some View {
        List {
            headerOptionsSection
            waanguContactsSection
            deviceContactsSection
            
            if viewModel.isPaginatable {
                loadMoreUsersView()
            }
        }
    }
    
    @ViewBuilder
    private var headerOptionsSection: some View {
        ForEach(ChatPartnerPickerOption.allCases) { item in
            HeaderItemView(item: item, translationService: translationService) {
                handleHeaderItemTap(item)
            }
        }
    }
    
    @ViewBuilder
    private var waanguContactsSection: some View {
        Section {
            ForEach(viewModel.waanguUsers) { user in
                waanguUserRow(user)
            }
        } header: {
            Text(t(ChatTranslationKeys.NEW_CHAT_CONTACTS_ON_WAANGU))
                .font(.headline)
                .textCase(nil)
                .bold()
        }
    }
    
    @ViewBuilder
    private var deviceContactsSection: some View {
        Section {
            ForEach(viewModel.deviceContacts) { user in
                deviceContactRow(user)
            }
        } header: {
            Text(t(ChatTranslationKeys.NEW_CHAT_INVITE_ON_WAANGU))
                .font(.headline)
                .textCase(nil)
                .bold()
        }
    }
    
    private func waanguUserRow(_ user: UserContactProps) -> some View {
        ChatPartnerRowView(user: user)
            .onTapGesture {
                handleWaanguUserTap(user)
            }
    }
    
    private func deviceContactRow(_ user: UserContactProps) -> some View {
        ChatPartnerRowView(user: user, trailingItems: {
            Button {
                // Invite action
            } label: {
                Text(t(ChatTranslationKeys.NEW_CHAT_INVITE))
            }
        })
    }
    
    private func handleHeaderItemTap(_ item: ChatPartnerPickerOption) {
        guard item == ChatPartnerPickerOption.newGroup else {
            return
        }
        viewModel.navStack.append(.groupPartnerPicker)
    }
    
    private func handleWaanguUserTap(_ user: UserContactProps) {
        dismiss()
        let route: ChatsTabRoute = .chatRoom(
            type: .direct(
                phoneNumber: user.phone,
                conversationId: nil,
                peer: DirectChatPeer(contact: user)
            ),
            isArchived: false
        )
        navigationCoord.push(route)
    }
    
    private func handleOnAppear() {
        Task {
            // Refresh contacts from server when opening new chat screen
            await viewModel.refreshContactsFromServer()
//            await viewModel.forceSyncContactsFromServer()
        }
        // Clear navigation and selections when screen appears
        viewModel.resetNavigationState()
    }
    
    private func loadMoreUsersView() -> some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .task {
                await viewModel.fetchUsers()
            }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }
}

@available(iOS 16.0, *)
extension ChatPartnerPickerScreen {
    @ViewBuilder
    private func destinationView(for route: ChannelCreationRoute) -> some View {
        switch route {
        case .groupPartnerPicker:
            GroupPartnerPickerScreen(viewModel: viewModel, translationService: translationService)
        case .setUpGroupChat:
            NewGroupSetUpScreen(viewModel: viewModel, translationService: translationService) { groupName, members, image, settings in
                dismiss()
                onCreateGroup(groupName, members, image, settings)
                // Clear navigation stack after group creation
                viewModel.resetNavigationState()
            }
        }
    }
}

@available(iOS 16.0, *)
extension ChatPartnerPickerScreen {
    @ToolbarContentBuilder
    private func trailingNavItem() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            cancelButton()
        }
    }
    
    private func cancelButton() -> some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.footnote)
                .foregroundStyle(.gray)
                .padding(8)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }
}

@available(iOS 16.0, *)
extension ChatPartnerPickerScreen {
    private struct HeaderItemView: View {
        let item: ChatPartnerPickerOption
        let translationService: (any TranslationServiceProtocol)?
        let onTapHandler: () -> Void
        
        var body: some View {
            Button {
                onTapHandler()
            } label: {
                buttonBody()
            }
        }
        
        private func buttonBody() -> some View {
            HStack {
                Image(systemName: item.imageName)
                    .font(.footnote)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
                
                Text(
                    translationService?.resolve(
                        key: item.title,
                        module: ChatTranslationKeys.MODULE
                    ).value ?? item.title
                )
            }
        }
    }
}

enum ChatPartnerPickerOption: String, CaseIterable, Identifiable {
    case newGroup = "New Group"
    case newContact = "New Contact"
    case newCommunity = "New Community"
    
    var id: String {
        return rawValue
    }
    
    var title: String {
        switch self {
        case .newGroup:
            return ChatTranslationKeys.NEW_CHAT_OPTION_GROUP
        case .newContact:
            return ChatTranslationKeys.NEW_CHAT_OPTION_CONTACT
        case .newCommunity:
            return ChatTranslationKeys.NEW_CHAT_OPTION_COMMUNITY
        }
    }
    
    var imageName: String {
        switch self {
        case .newGroup:
            return "person.2.fill"
        case .newContact:
            return "person.fill.badge.plus"
        case .newCommunity:
            return "person.3.fill"
        }
    }
}

