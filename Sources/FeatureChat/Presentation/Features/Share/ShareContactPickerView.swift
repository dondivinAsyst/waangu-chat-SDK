//
//  ShareContactPickerView.swift
//  FeatureChat
//
//  View for selecting contacts/chats to share content with
//

import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct ShareContactPickerView: View {
    @State private var searchText = ""
    @State private var viewModel: ChatPartnerPickerViewModel
    private let translationService: (any TranslationServiceProtocol)?
    
    let coordinator: ChatCoordinator
    let onDismiss: () -> Void
    
    init(coordinator: ChatCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
        self._viewModel = State(initialValue: coordinator.feature.makeChatPartnerPickerViewModel())
        self.translationService = coordinator.feature.translationService
    }
    
    var body: some View {
        VStack {
            mainListView
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: t(ChatTranslationKeys.SHARE_SEARCH_PLACEHOLDER))
        .onChange(of: searchText) { _ in
            viewModel.searchContacts(searchText)
        }
        .navigationTitle(t(ChatTranslationKeys.SHARE_TITLE))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                cancelButton()
            }
        }
        .onAppear {
            handleOnAppear()
        }
    }
    
    @ViewBuilder
    private var mainListView: some View {
        List {
            recentChatsSection
            waanguContactsSection
            
            if viewModel.isPaginatable {
                loadMoreUsersView()
            }
        }
    }
    
    @ViewBuilder
    private var recentChatsSection: some View {
        Section {
            // TODO: Show recent chats for easier sharing
            Text(t(ChatTranslationKeys.SHARE_RECENT_TODO))
                .foregroundColor(.secondary)
                .font(.caption)
        } header: {
            Text(t(ChatTranslationKeys.SHARE_RECENT))
                .font(.headline)
                .textCase(nil)
                .bold()
        }
    }
    
    @ViewBuilder
    private var waanguContactsSection: some View {
        Section {
            ForEach(viewModel.waanguUsers) { user in
                waanguUserRow(user)
            }
        } header: {
            Text(t(ChatTranslationKeys.SHARE_CONTACTS_ON_WAANGU))
                .font(.headline)
                .textCase(nil)
                .bold()
        }
    }
    
    private func waanguUserRow(_ user: UserContactProps) -> some View {
        ChatPartnerRowView(user: user)
            .onTapGesture {
                handleUserSelection(user)
            }
    }
    
    private func handleUserSelection(_ user: UserContactProps) {
        Task {
            await processShareForUser(user)
        }
    }
    
    @MainActor
    private func processShareForUser(_ user: UserContactProps) async {
        // If we have shared content URL, process it
        if let sharedUrl = coordinator.sharedContentUrl {
            do {
                let shareProcessor = coordinator.feature.makeShareContentProcessor()
                try await shareProcessor.processSharedContent(from: sharedUrl)
                
                // Navigate to the chat room after successful share
                let route: ChatsTabRoute = .chatRoom(
                    type: .direct(
                        phoneNumber: user.phone,
                        conversationId: nil,
                        peer: DirectChatPeer(contact: user)
                    ),
                    isArchived: false
                )
                coordinator.chatsTabCoordinator.push(route)
                
                // Dismiss the share sheet
                onDismiss()
                
            } catch {
                debugLog("Error processing shared content: \(error)")
                // TODO: Show error alert
            }
        } else {
            // No shared content, just navigate to chat
            let route: ChatsTabRoute = .chatRoom(
                type: .direct(
                    phoneNumber: user.phone,
                    conversationId: nil,
                    peer: DirectChatPeer(contact: user)
                ),
                isArchived: false
            )
            coordinator.chatsTabCoordinator.push(route)
            onDismiss()
        }
    }
    
    private func handleOnAppear() {
        Task {
            await viewModel.refreshContactsFromServer()
        }
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
    
    private func cancelButton() -> some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.footnote)
                .foregroundStyle(.gray)
                .padding(8)
                .background(Color(.systemGray5))
                .clipShape(Circle())
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

#Preview {
    NavigationStack {
        EmptyView()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}