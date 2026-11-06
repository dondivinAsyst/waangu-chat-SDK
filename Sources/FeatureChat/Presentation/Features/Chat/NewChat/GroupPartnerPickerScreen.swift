//
//  AddGroupChatPartnersScreen.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 12.01.2025.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct GroupPartnerPickerScreen: View {
    @ObservedObject var viewModel: ChatPartnerPickerViewModel
    let translationService: (any TranslationServiceProtocol)?
    @State private var searchText = ""
    
    var body: some View {
        List {
            if viewModel.showSelectedUsers {
                SelectedChatPartnerView(users: viewModel.selectedChatPartners) { user in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.handleItemSelection(user)
                    }
                }
            }
            
            Section {
                ForEach(viewModel.waanguUsers) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.handleItemSelection(item)
                        }
                    } label: {
                        chatPartnerRowView(item)
                    }
                    .buttonStyle(PlainButtonStyle()) // ✅ Prevents default button highlight
                }
            }
            
            if viewModel.isPaginatable {
                loadMoreUsersView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showSelectedUsers)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedChatPartners.count) // ✅ Animate selection changes
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: t(ChatTranslationKeys.NEW_CHAT_SEARCH_PLACEHOLDER))
        .onChange(of: searchText) { _ in
            viewModel.searchContacts(searchText)
        }
        .toolbar {
            titleView()
            trailingNavItem()
        }
    }
    
    private func chatPartnerRowView(_ user: UserContactProps) -> some View {
        ChatPartnerRowView(user: user) {
            Spacer()
            let isSelected = viewModel.isUserSelected(user)
            
            // ✅ Animated selection indicator with primary color
            ZStack {
                // Background circle
                Circle()
                    .stroke(isSelected ? AppColors.primary : Color(.systemGray4), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                // Checkmark with scale animation
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(AppColors.primary)
                        .clipShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .contentShape(Rectangle()) // ✅ Makes entire row tappable
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

extension GroupPartnerPickerScreen {
    @ToolbarContentBuilder
    private func titleView() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack {
                Text(t(ChatTranslationKeys.GROUP_PICKER_ADD_PARTICIPANTS))
                    .bold()
                
                let count = viewModel.selectedChatPartners.count
                let maxCount = ChannelContants.maxGroupChatMembers
                
                Text(t(ChatTranslationKeys.GROUP_PICKER_SELECTED_COUNT, args: ["\(count)", "\(maxCount)"]))
                    .foregroundStyle(.gray)
                    .font(.footnote)
            }
        }
    }
    
    @ToolbarContentBuilder
    private func trailingNavItem() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(t(ChatTranslationKeys.GROUP_PICKER_NEXT)) {
                viewModel.navStack.append(.setUpGroupChat)
            }
            .bold()
            .disabled(viewModel.selectedChatPartners.isEmpty)
        }
    }
}

//#Preview {
//    NavigationStack {
//        GroupPartnerPickerScreen(viewModel: ChatPartnerPickerViewModel())
//    }
//}
