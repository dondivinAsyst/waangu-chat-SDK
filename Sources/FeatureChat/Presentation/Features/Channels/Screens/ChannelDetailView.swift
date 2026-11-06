//
//  ChannelDetailView.swift
//  FeatureChat
//
//  Channel info — reached from the room, which is the channel itself.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit
import UIKit

/// What a channel is, who follows it, and the handful of things a reader or its
/// owner can do about it.
///
/// Reached from the room's header, so it deliberately has no "open channel"
/// action: the reader came from there.
@available(iOS 16.0, *)
struct ChannelDetailView: View {

    @StateObject private var viewModel: ChannelRoomViewModel
    /// The admin picker lists the same contacts every other picker does.
    let contactsUseCases: ContactsUseCasesProtocol
    let onUnfollowed: () -> Void

    @State private var showShare = false
    @State private var showEdit = false
    @State private var showInviteAdmins = false
    @State private var showInviteContacts = false
    @State private var showInviteLink = false

    init(
        viewModel: ChannelRoomViewModel,
        contactsUseCases: ContactsUseCasesProtocol,
        onUnfollowed: @escaping () -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.contactsUseCases = contactsUseCases
        self.onUnfollowed = onUnfollowed
    }

    var body: some View {
        List {
            header()
            actions()
            descriptionSection()
            inviteLinkSection()
            adminsSection()
            settings()
            about()

            if let channel = viewModel.channel,
               !channel.isOwned(by: CurrentSessionInfo.shared.currentUid),
               channel.isSubscribed {
                Section {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.unfollow()
                            onUnfollowed()
                        }
                    } label: {
                        Text(t(ChatTranslationKeys.CHANNELS_UNFOLLOW))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t(ChatTranslationKeys.CHANNELS_INFO))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.onAppear() }
        .task { await viewModel.loadAdmins() }
        .refreshable { await viewModel.load() }
        .chatAppearanceSheet(isPresented: $showShare) {
            if let channel = viewModel.channel {
                ActivityShareSheet(activityItems: [channel.name])
            }
        }
        .chatAppearanceSheet(isPresented: $showInviteAdmins) {
            ChannelInviteAdminsSheet(
                viewModel: viewModel,
                contactsUseCases: contactsUseCases,
                onDismiss: { showInviteAdmins = false }
            )
        }
        .chatAppearanceSheet(isPresented: $showInviteContacts) {
            if let channel = viewModel.channel {
                ChannelInviteContactsSheet(
                    channel: channel,
                    viewModel: viewModel.channelsViewModel,
                    contactsUseCases: contactsUseCases,
                    translationService: viewModel.translationService
                )
            }
        }
        .chatAppearanceSheet(isPresented: $showInviteLink) {
            if let channel = viewModel.channel {
                ChannelInviteLinkSheet(
                    viewModel: ChannelInviteLinkViewModel(
                        channel: channel,
                        channelUseCases: viewModel.channelUseCases
                    )
                )
            }
        }
        .chatAppearanceSheet(isPresented: $showEdit) {
            if let channel = viewModel.channel {
                ChannelEditSheet(
                    channel: channel,
                    viewModel: viewModel,
                    onDismiss: { showEdit = false }
                )
            }
        }
        .customAlert(
            title: common("error"),
            message: viewModel.errorMessage,
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { viewModel.dismissError() }
        )
    }

    // MARK: - Sections

    @ViewBuilder
    private func header() -> some View {
        Section {
            VStack(spacing: 10) {
                CircularProfileImageView(viewModel.channel?.image, size: .xLarge)

                Text(viewModel.channel?.name ?? "")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                // The full figure here, unlike the header's 120K: this is the
                // screen someone opens to read the number.
                Text(t(
                    ChatTranslationKeys.CHANNELS_FOLLOWER_COUNT,
                    args: [Self.grouped(viewModel.followerCount)]
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func actions() -> some View {
        Section {
            HStack(spacing: 10) {
                if let channel = viewModel.channel {
                    if channel.isOwned(by: CurrentSessionInfo.shared.currentUid) {
                        tile(
                            title: t(ChatTranslationKeys.CHANNELS_EDIT),
                            systemImage: "pencil"
                        ) { showEdit = true }
                    } else {
                        tile(
                            title: channel.isSubscribed
                                ? t(ChatTranslationKeys.CHANNELS_FOLLOWING)
                                : t(ChatTranslationKeys.CHANNELS_FOLLOW),
                            systemImage: channel.isSubscribed ? "checkmark" : "plus"
                        ) {
                            Task { await viewModel.toggleFollow() }
                        }
                    }
                    
                    // Invite Contacts button - only for channel owners
                    if channel.isOwned(by: CurrentSessionInfo.shared.currentUid) {
                        tile(
                            title: t(ChatTranslationKeys.CHANNELS_INVITE_CONTACTS),
                            systemImage: "person.crop.circle.badge.plus"
                        ) { showInviteContacts = true }
                    }
                }

                tile(title: t(ChatTranslationKeys.CHANNELS_SHARE_CHANNEL), systemImage: "square.and.arrow.up") {
                    showShare = true
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    /// What the channel says about itself.
    @ViewBuilder
    private func descriptionSection() -> some View {
        if let description = viewModel.channel?.description, !description.isEmpty {
            Section {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }
    
    /// Shareable invite link section - only for channel owners.
    ///
    /// Allows owners to generate, share, and manage external invite links that
    /// can be shared via WhatsApp, SMS, etc. Recipients can join the channel by
    /// opening the link.
    @ViewBuilder
    private func inviteLinkSection() -> some View {
        if let channel = viewModel.channel,
           channel.isOwned(by: CurrentSessionInfo.shared.currentUid) {
            Section {
                Button {
                    showInviteLink = true
                } label: {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 28)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t(ChatTranslationKeys.CHANNELS_INVITE_LINK))
                                .font(.body)
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Text(t(ChatTranslationKeys.CHANNELS_INVITE_LINK_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text(t(ChatTranslationKeys.CHANNELS_INVITE))
            } footer: {
                Text(t(ChatTranslationKeys.CHANNELS_INVITE_LINK_FOOTER))
            }
        }
    }

    /// Who else may post. Owner-only: an admin list a follower cannot change is
    /// a list a follower does not need.
    @ViewBuilder
    private func adminsSection() -> some View {
        if let channel = viewModel.channel,
           channel.isOwned(by: CurrentSessionInfo.shared.currentUid) {
            Section {
                if viewModel.admins.isEmpty {
                    Text(t(ChatTranslationKeys.CHANNELS_NO_ADMINS))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.admins) { admin in
                        HStack {
                            Text(admin.userName.isEmpty ? admin.userId : admin.userName)
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            Button(role: .destructive) {
                                Task { await viewModel.removeAdmin(userId: admin.userId) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    showInviteAdmins = true
                } label: {
                    Label(
                        t(ChatTranslationKeys.CHANNELS_INVITE_ADMINS),
                        systemImage: "person.badge.plus"
                    )
                    .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            } header: {
                Text(t(ChatTranslationKeys.CHANNELS_ADMINS))
            }
        }
    }

    @ViewBuilder
    private func settings() -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.isMuted },
                set: { _ in Task { await viewModel.toggleMute() } }
            )) {
                Label(t(ChatTranslationKeys.CHANNELS_MUTED), systemImage: "bell.slash")
            }
            .tint(AppColors.primary)
        }
    }

    /// Two facts about every channel, stated rather than configurable: both are
    /// how Identity builds channels, not settings this app can change.
    @ViewBuilder
    private func about() -> some View {
        Section {
            explainer(
                systemImage: "globe",
                title: t(ChatTranslationKeys.CHANNELS_PUBLIC_TITLE),
                detail: t(ChatTranslationKeys.CHANNELS_PUBLIC_DESC)
            )

            explainer(
                systemImage: "lock.shield",
                title: t(ChatTranslationKeys.CHANNELS_PRIVACY_TITLE),
                detail: t(ChatTranslationKeys.CHANNELS_PRIVACY_DESC)
            )
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func tile(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.primary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func explainer(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func grouped(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    /// Shared strings live in the common module, not the chat one.
    private func common(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
