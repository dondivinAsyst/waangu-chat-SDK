//
//  ChannelsViewModel.swift
//  FeatureChat
//

import Foundation
import UIKit
import WaanguCoreKit

/// A followed channel as the Updates list draws it.
///
/// The name and avatar come from Identity, the preview line, the time and the
/// unread count from the channel's conversation in the inbox — the same source
/// the chats list reads. Neither half can draw the row on its own.
struct FollowedChannel: Identifiable, Equatable {

    let channel: Channel
    let preview: ConversationPreview

    var id: String { channel.id }
}

/// Canaux Updates: the ones this user follows, and the directory to find more.
///
/// "Followed" is not a field Identity sends — it is the presence of the
/// channel's `BROADCAST` conversation in the inbox, which the repository
/// resolves. So a subscribe only shows up here once the inbox sync has run.
@available(iOS 16.0, *)
@MainActor
public final class ChannelsViewModel: ObservableObject {

    @Published private(set) var subscribed: [Channel] = []
    /// The followed channels with their inbox preview, in most-recent order.
    @Published private(set) var followed: [FollowedChannel] = []
    @Published private(set) var discovered: [Channel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// Why the channel list could not be read, shown in place of the list with
    /// a retry. Kept apart from `errorMessage`, which is an alert: a background
    /// read that fails must not throw a modal over a screen the user just opened.
    @Published private(set) var loadError: String?
    /// Suggestions the user waved away, for as long as this screen lives.
    @Published private var dismissedSuggestions: Set<String> = []

    private let useCases: ChannelUseCasesProtocol
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let conversationRoomUseCases: ConversationRoomUseCasesProtocol
    /// Parks an avatar in media storage and hands back its URL.
    private let uploadAvatar: UploadProfilePhotoUseCaseProtocol
    let translationService: (any TranslationServiceProtocol)?

    init(
        useCases: ChannelUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        conversationRoomUseCases: ConversationRoomUseCasesProtocol,
        uploadAvatar: UploadProfilePhotoUseCaseProtocol,
        translationService: (any TranslationServiceProtocol)?
    ) {
        self.useCases = useCases
        self.discussionUseCases = discussionUseCases
        self.conversationRoomUseCases = conversationRoomUseCases
        self.uploadAvatar = uploadAvatar
        self.translationService = translationService
    }

    /// Channels the user does not follow yet — what the explore list shows.
    ///
    /// Dismissed ones stay out for this session only: "not interested" is a
    /// nudge about the list in front of you, and Identity has nowhere to record
    /// it.
    var suggestions: [Channel] {
        discovered.filter { !$0.isSubscribed && !dismissedSuggestions.contains($0.id) }
    }

    func dismissSuggestion(_ channel: Channel) {
        dismissedSuggestions.insert(channel.id)
    }

    // MARK: - Loading

    func onAppear() {
        Task { await load() }
    }

    func load() async {
        isLoading = followed.isEmpty && discovered.isEmpty
        defer { isLoading = false }

        do {
            // The directory read also resolves `isSubscribed`, so it has to come
            // first: the followed list is a filter over the same data.
            discovered = try await useCases.listChannels.execute(page: 0, size: 50)
            subscribed = try await useCases.listSubscribed.execute()
            // Persist every followed channel now, not only the one whose room a
            // reader happens to open. Without this a channel stayed invisible to
            // the local inbox — and unable to receive a broadcast at all, for
            // want of a row to attach it to — until it was opened once. Already
            // persisted channels are left untouched: this only creates rows that
            // are missing, never rewrites one that exists.
            await ChannelLocalConversationSync.ensureAll(subscribed, discussionUseCases: discussionUseCases)
            followed = await withPreviews(subscribed)
            loadError = nil
        } catch {
            if subscribed.isEmpty && discovered.isEmpty {
                loadError = message(for: error)
            }
        }
    }

    // MARK: - Actions

    /// The avatar is uploaded first — the channel carries its URL, and a failed
    /// upload must not create a channel without the picture the user chose.
    func create(_ draft: NewChannelDraft, avatar: UIImage?) async -> Channel? {
        isWorking = true
        defer { isWorking = false }

        var draft = draft
        if let avatar {
            switch await uploadAvatar.execute(imageData: ChatImageSendEncoder.encodeAvatar(avatar)) {
            case .failure(let error):
                errorMessage = error.localizedDescription
                return nil
            case .success(let url):
                draft.image = url
            }
        }

        do {
            let channel = try await useCases.createChannel.execute(draft)
            await load()
            errorMessage = nil
            return channel
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    func toggleSubscription(_ channel: Channel) async {
        isWorking = true
        defer { isWorking = false }

        do {
            if channel.isSubscribed {
                _ = try await useCases.subscription.unsubscribe(channelId: channel.id)
            } else {
                _ = try await useCases.subscription.subscribe(channelId: channel.id)
            }
            await load()
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// The conversation to open, or nil with `errorMessage` set when the channel
    /// has none — a channel created before Identity's V12 migration.
    func conversationId(for channel: Channel) async -> String? {
        do {
            return try await useCases.openConversation.execute(channelId: channel.id)
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    func channel(id: String) async -> Channel? {
        do {
            return try await useCases.getChannel.execute(channelId: id)
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func message(for error: Error) -> String {
        (error as? ChannelError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Inbox previews

    /// Joins each channel to its conversation in the inbox.
    ///
    /// A channel whose conversation has not synced yet still appears, with an
    /// empty preview: it was subscribed, and hiding it would look like the
    /// subscribe failed.
    private func withPreviews(_ channels: [Channel]) async -> [FollowedChannel] {
        let discussions = (try? await discussionUseCases.getDiscussions.execute()) ?? []
        let previews = ConversationPreview.index(discussions)

        return channels
            .map { channel in
                FollowedChannel(
                    channel: channel,
                    preview: channel.conversationId.flatMap { previews[$0] } ?? .empty
                )
            }
            .sorted { lhs, rhs in
                // Your own channel leads: it is the one you post to, and the
                // one you look for first after creating it.
                let currentUserId = CurrentSessionInfo.shared.currentUid
                let lhsOwned = lhs.channel.isOwned(by: currentUserId)
                let rhsOwned = rhs.channel.isOwned(by: currentUserId)
                if lhsOwned != rhsOwned { return lhsOwned }
                return lhs.preview.unreadCount > rhs.preview.unreadCount
            }
    }

    // MARK: - Channel Invitations

    /// Sends channel invitation messages to selected contacts via DM.
    ///
    /// Creates a CHANNEL_INVITE message for each contact. The system will
    /// automatically create a DM conversation if one doesn't exist.
    func sendChannelInvites(inviteContent: ChannelInviteContent, toContactIds contactIds: [String]) async {
        isWorking = true
        defer { isWorking = false }

        for contactId in contactIds {
            // Create message content with channel invite
            let messageContent = MessageContent(channelInvite: inviteContent)
            
            // Create the send message request
            // For DM, we use the contact's userId as both conversationId and recipientId
            // The backend will create the conversation if it doesn't exist
            let request = SendMessageRequest(
                content: messageContent,
                type: .CHANNEL_INVITE,
                conversationId: contactId, // Use contactId; backend creates conversation if needed
                receiver: UserRoom(
                    idContact: contactId,
                    userId: contactId,
                    phone: nil,
                    name: nil,
                    avatar: nil,
                    description: nil,
                    isOnline: false,
                    onlineStatus: UserOnline(status: .offline, lastSeen: "", userId: contactId),
                    isBlocked: false
                ),
                kind: .direct,
                reply: nil,
                recipientId: contactId,
                messageCode: nil,
                forwarded: false
            )
            
            // Send the invitation message
            await conversationRoomUseCases.sendMessage.execute(request)
        }
        
        errorMessage = nil
    }

}
