//
//  ChannelInviteContactsSheet.swift
//  FeatureChat
//
//  Created by Kiro on 9/30/26.
//  Contact selection sheet for sending channel invitations via DM
//

import SwiftUI
import Foundation
import WaanguSharedUI
import WaanguCoreKit

/// Sheet for selecting contacts to invite to a channel.
/// Sends a CHANNEL_INVITE message to each selected contact's DM conversation.
struct ChannelInviteContactsSheet: View {
    let channel: Channel
    @ObservedObject var viewModel: ChannelsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @State private var selectedContacts: Set<String> = [] // Contact IDs
    @State private var isLoading: Bool = false
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @State private var contacts: [WaanguContact] = []
    
    private let contactsUseCases: ContactsUseCasesProtocol
    private let translationService: TranslationServiceProtocol?
    
    init(
        channel: Channel,
        viewModel: ChannelsViewModel,
        contactsUseCases: ContactsUseCasesProtocol,
        translationService: TranslationServiceProtocol?
    ) {
        self.channel = channel
        self.viewModel = viewModel
        self.contactsUseCases = contactsUseCases
        self.translationService = translationService
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    searchBar
                    contactsList
                    
                    // Bottom padding when contacts are selected
                    if !selectedContacts.isEmpty {
                        Color.clear.frame(height: 100)
                    }
                }
                
                if !selectedContacts.isEmpty {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle(t("channel.invite.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(common("cancel")) {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                    .disabled(isSending)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedContacts.count)
            .task {
                await loadContacts()
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 15))
            
            TextField(t("channel.invite.search_placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
            
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Contacts List
    
    private var contactsList: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text(t("channel.invite.loading"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            } else if let errorMessage = errorMessage {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button(common("retry")) {
                            Task { await loadContacts() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            } else if filteredContacts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? t("channel.invite.empty_title") : t("channel.invite.no_results"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? t("channel.invite.empty_subtitle") : t("channel.invite.no_results_subtitle"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
                    }
                } header: {
                    Text(t("channel.invite.section_contacts"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                        .padding(.bottom, 2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await loadContacts()
        }
    }
    
    private func contactRow(_ contact: WaanguContact) -> some View {
        let isSelected = selectedContacts.contains(contact.id)
        return HStack(spacing: 12) {
            // Avatar
            CircularProfileImageView(
                contact.image,
                size: .custom(44)
            )
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                if !contact.phone.isEmpty {
                    Text(contact.phone)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Selection indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? AppColors.primary : Color(.systemGray3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                if isSelected {
                    Circle()
                        .fill(AppColors.primary)
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                toggleSelection(contact)
            }
        }
        .listRowBackground(
            isSelected ? Color(.systemGray5).opacity(0.6) : Color(.systemGray6)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(alignment: .center, spacing: 12) {
                // Selected count and names
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("channel.invite.selected_count", args: ["\(selectedContacts.count)"]))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(selectedContactNames)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .animation(.easeInOut(duration: 0.2), value: selectedContactNames)
                
                Spacer()
                
                // Send button
                Button {
                    Task { await sendInvites() }
                } label: {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 80)
                    } else {
                        Text(t("channel.invite.send"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(minWidth: 80)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(AppColors.primary)
                            )
                    }
                }
                .disabled(selectedContacts.isEmpty || isSending)
                .opacity(selectedContacts.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredContacts: [WaanguContact] {
        guard !searchText.isEmpty else {
            return contacts
        }
        
        let lowercasedSearch = searchText.lowercased()
        return contacts.filter { contact in
            contact.name.lowercased().contains(lowercasedSearch) ||
            contact.phone.contains(searchText)
        }
    }
    
    private var selectedContactNames: String {
        let names = selectedContacts.compactMap { id in
            contacts.first(where: { $0.id == id })?.name
        }
        return names.joined(separator: ", ")
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ contact: WaanguContact) {
        if selectedContacts.contains(contact.id) {
            selectedContacts.remove(contact.id)
        } else {
            selectedContacts.insert(contact.id)
        }
    }
    
    private func loadContacts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await contactsUseCases.getPersistedContacts.execute()
            
            if let (waanguContacts, _) = result {
                // Filter out contacts who are already channel subscribers
                let subscriberIds = Set(channel.subscriberIds ?? [])
                contacts = waanguContacts.filter { !subscriberIds.contains($0.id) }
            } else {
                contacts = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func sendInvites() async {
        guard !selectedContacts.isEmpty else { return }
        
        isSending = true
        errorMessage = nil
        
        // Create channel invite content
        let inviteContent = ChannelInviteContent(
            channelId: channel.id,
            channelName: channel.name,
            channelImage: channel.image,
            channelDescription: channel.description,
            followerCount: channel.subscriberCount,
            invitedBy: channel.createdByUserId,
            inviterName: "", // TODO: Get current user name
            invitedAt: Date()
        )
        
        // Send invites through the view model
        await viewModel.sendChannelInvites(
            inviteContent: inviteContent,
            toContactIds: Array(selectedContacts)
        )
        
        isSending = false
        dismiss()
    }
    
    // MARK: - Translation Helpers
    
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }
    
    private func common(_ key: String) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.COMMON_MODULE
        ).value ?? key.capitalized
    }
}
