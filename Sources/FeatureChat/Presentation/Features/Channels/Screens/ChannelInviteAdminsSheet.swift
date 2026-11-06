//
//  ChannelInviteAdminsSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Picks a contact to make an admin of a channel.
///
/// Identity has no channel-admin route yet, so the result is held by the debug
/// mock store — the screen and the use case are the real ones.
@available(iOS 16.0, *)
struct ChannelInviteAdminsSheet: View {

    @ObservedObject var viewModel: ChannelRoomViewModel
    let contactsUseCases: ContactsUseCasesProtocol
    let onDismiss: () -> Void

    @State private var contacts: [UserContactProps] = []
    @State private var search = ""

    private var visible: [UserContactProps] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if contacts.isEmpty && search.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(t(ChatTranslationKeys.CHANNELS_NO_FOLLOWERS_FOR_ADMIN))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(t(ChatTranslationKeys.CHANNELS_NO_FOLLOWERS_FOR_ADMIN_DESC))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(visible) { contact in
                        Button {
                            Task {
                                await viewModel.addAdmin(userId: contact.userId, userName: contact.name)
                                onDismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CircularProfileImageView(contact.avatar, size: .xSmall)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(contact.phone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search)
            .navigationTitle(t(ChatTranslationKeys.CHANNELS_INVITE_ADMINS))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel"), action: onDismiss)
                }
            }
            .task { await load() }
        }
    }

    /// Only registered users who are already followers can be made admins.
    /// Admins are selected FROM existing subscribers (channel.subscriberIds), not all contacts.
    /// An admin has to be a follower first to post to the channel.
    private func load() async {
        let stored = try? await contactsUseCases.getPersistedContacts.execute()
        let allContacts = stored?.UserContactProps ?? []
        
        // Filter to only show contacts who are subscribers of this channel
        if let subscriberIds = viewModel.channel?.subscriberIds {
            let subscriberIdSet = Set(subscriberIds)
            contacts = allContacts.filter { subscriberIdSet.contains($0.userId) }
        } else {
            // If subscriberIds is nil, show no contacts (or fetch from server)
            contacts = []
        }
    }

    private func t(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
