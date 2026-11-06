//
//  ChannelRoomViewModel.swift
//  FeatureChat
//

import Foundation
import Combine
import UIKit
import WaanguCoreKit

/// A channel's room: its posts, and the channel record behind them.
///
/// Owns its messages through `ConversationRoomUseCases` — the same use cases the
/// chat room calls. Message handling lives there, not in either view model, so a
/// broadcast needs neither a copy of that logic nor a borrowed `ChatRoomViewModel`
/// carrying a conversation's worth of behaviour a channel does not have.
@MainActor
public final class ChannelRoomViewModel: ObservableObject, ForwardMessageSource {

    @Published private(set) var channel: Channel?
    @Published private(set) var posts: [MessageDataItem] = []
    /// Composer sheets. Owned here, like the chat room owns its own — the input
    /// bar only asks for them.
    @Published var showAttachments = false
    @Published var showCamera = false
    @Published var galleryEditorPreview: PreviewMediaItem?
    @Published var documentPreviewURL: URL?
    /// The post the reader chose to forward, held while the picker is up.
    @Published var postBeingForwarded: MessageDataItem?
    @Published private(set) var isLoading = true
    /// Views per post, keyed by `codeMessage`, refreshed with the room.
    @Published private(set) var viewCounts: [String: Int] = [:]
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    /// Whether this user has muted the channel. Stored per conversation, like
    /// any other room's mute.
    @Published private(set) var isMuted = false

    private let channelId: String
    let channelUseCases: ChannelUseCasesProtocol
    /// Parks an avatar in media storage and hands back its URL.
    private let uploadAvatar: UploadProfilePhotoUseCaseProtocol
    private let roomUseCases: ConversationRoomUseCasesProtocol
    private let messagesUseCases: MessagesUseCasesProtocol
    /// Records the owner's voice posts. The bar drives it; the flow below turns
    /// the result into a message.
    let voiceRecordingViewModel: VoiceRecordingViewModel
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let postViews: any ChannelPostViewCounting
    let translationService: (any TranslationServiceProtocol)?
    /// Handles channel-wide operations like sending invites
    let channelsViewModel: ChannelsViewModel

    private var conversationId: String?
    private var observationTask: Task<Void, Never>?
    /// Holds the recording between "stopped" and "sent"; the flow reads it back.
    private let voiceAttachments = ChatRoomVoiceAttachmentStore()
    /// Built once the conversation is known — it is keyed on that id.
    private var composer: ConversationMessageComposer?
    private lazy var forwarding = MessageForwardingService(sendMessage: roomUseCases.sendMessage)

    public init(
        channelId: String,
        channelUseCases: ChannelUseCasesProtocol,
        uploadAvatar: UploadProfilePhotoUseCaseProtocol,
        roomUseCases: ConversationRoomUseCasesProtocol,
        messagesUseCases: MessagesUseCasesProtocol,
        voiceRecordingViewModel: VoiceRecordingViewModel,
        discussionUseCases: DiscussionUseCasesProtocol,
        postViews: any ChannelPostViewCounting,
        translationService: (any TranslationServiceProtocol)?,
        channelsViewModel: ChannelsViewModel
    ) {
        self.channelId = channelId
        self.channelUseCases = channelUseCases
        self.uploadAvatar = uploadAvatar
        self.roomUseCases = roomUseCases
        self.messagesUseCases = messagesUseCases
        self.voiceRecordingViewModel = voiceRecordingViewModel
        self.discussionUseCases = discussionUseCases
        self.postViews = postViews
        self.translationService = translationService
        self.channelsViewModel = channelsViewModel
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard channel == nil else {
            // Already loaded: refresh the record so the follower count is the
            // one the server has now, not the one it had when this room opened.
            Task { await refreshChannel() }
            return
        }
        Task { await load() }
    }

    /// Re-reads the channel record alone — no messages, no observation.
    func refreshChannel() async {
        guard let refreshed = try? await channelUseCases.getChannel.execute(channelId: channelId) else {
            return
        }
        channel = refreshed
    }

    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Only the channel's creator gets a composer. Core is expected to enforce
    /// this too — this decides what to offer, never what is allowed.
    var canPost: Bool {
        channel?.canPost(as: CurrentSessionInfo.shared.currentUid) ?? false
    }

    var followerCount: Int {
        channel?.subscriberCount ?? 0
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Loading

    func load() async {
        defer { isLoading = false }

        do {
            let channel = try await channelUseCases.getChannel.execute(channelId: channelId)

            guard let conversationId = channel.conversationId, !conversationId.isEmpty else {
                self.channel = channel
                errorMessage = ChannelError.missingConversation.errorDescription
                return
            }
            self.conversationId = conversationId

            // Before the channel is published, not after: publishing it is what
            // builds the chat engine, and the engine writes into this row.
            await ensureLocalConversation(conversationId: conversationId, channel: channel)
            composer = ConversationMessageComposer(
                conversationId: conversationId,
                kind: .channel,
                sendMessage: roomUseCases.sendMessage,
                onError: { [weak self] message in self?.errorMessage = message }
            )
            self.channel = channel

            await loadFirstPage(conversationId: conversationId)
            observe(conversationId: conversationId)
            await loadMuteState(conversationId: conversationId)
            await refreshViewCounts()
        } catch {
            errorMessage = message(for: error)
        }
    }






    // MARK: - Mute

    func toggleMute() async {
        guard let conversationId else { return }
        let next = !isMuted

        do {
            guard var discussion = try await discussion(for: conversationId) else { return }
            var setting = discussion.setting ?? UserConversationSetting()
            setting.isMuted = next
            discussion.setting = setting
            try await discussionUseCases.updateDiscussionSetting.execute(discussion: discussion)
            isMuted = next
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func loadMuteState(conversationId: String) async {
        isMuted = (try? await discussion(for: conversationId))??.setting?.isMuted ?? false
    }

    private func discussion(for conversationId: String) async throws -> DiscussionChatItem? {
        try await discussionUseCases.getDiscussions.execute()?
            .first { $0.conversationId == conversationId }
    }

    // MARK: - Editing

    /// Renames the channel or changes its picture. Owner only — `PUT /channels`
    /// is refused for anyone else, and the edit action is not offered.
    func updateChannel(name: String, description: String?, avatar: UIImage?) async {
        isSending = true
        defer { isSending = false }

        var imageUrl: String?
        if let avatar {
            if case .success(let url) = await uploadAvatar.execute(
                imageData: ChatImageSendEncoder.encodeAvatar(avatar)
            ) {
                imageUrl = url
            }
        }

        do {
            channel = try await channelUseCases.updateChannel.execute(
                channelId: channelId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: nil,
                image: imageUrl,
                description: description
            )
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Following

    /// Follows or unfollows, depending on where this channel currently stands.
    func toggleFollow() async {
        guard let channel else { return }
        do {
            if channel.isSubscribed {
                _ = try await channelUseCases.subscription.unsubscribe(channelId: channelId)
            } else {
                _ = try await channelUseCases.subscription.subscribe(channelId: channelId)
            }
            self.channel = try await channelUseCases.getChannel.execute(channelId: channelId)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func unfollow() async {
        do {
            _ = try await channelUseCases.subscription.unsubscribe(channelId: channelId)
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Posts

    private func loadFirstPage(conversationId: String) async {
        do {
            let page = try await roomUseCases.loadMessagesPage.execute(
                conversationId: conversationId,
                before: nil,
                pageSize: Self.pageSize
            )
            posts = Self.oldestFirst(page.messages)
            await markRead()
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Older posts, once the reader reaches the top of what is loaded.
    func loadOlderPosts() async {
        guard let conversationId, let oldest = posts.first?.createdAt else { return }

        do {
            let page = try await roomUseCases.loadMessagesPage.execute(
                conversationId: conversationId,
                before: oldest,
                pageSize: Self.pageSize
            )
            guard !page.messages.isEmpty else { return }
            posts = Self.oldestFirst(page.messages + posts)
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// The store observation: every local write lands here, which is what an
    /// incoming broadcast becomes once the sync has stored it.
    private func observe(conversationId: String) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await result in self.roomUseCases.observeMessages.execute(conversationId: conversationId) {
                guard case .success(let items) = result else { continue }
                await MainActor.run {
                    self.posts = Self.oldestFirst(items)
                }
                await self.markRead()
                await self.refreshViewCounts()
            }
        }
    }

    /// Publishes a post. Owner only — the composer is not offered otherwise.
    func post(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversationId, canPost else { return }

        isSending = true
        defer { isSending = false }

        composer?.send(MessageContent(text: trimmed), type: .TEXT)
    }

    // MARK: - Posting
    //
    // Composing is `ConversationMessageComposer`'s job — the same one the chat
    // room uses. This room only says when, and supplies the broadcast context:
    // no peer, no recipient, no reply.

    func onOpenAttachments() {
        ChatKeyboard.hide()
        showAttachments = true
    }

    func onOpenCamera() {
        ChatKeyboard.hide()
        showCamera = true
    }

    func closeAttachments() {
        showAttachments = false
    }

    func closeCamera() {
        showCamera = false
    }

    /// Opens the editor on a picked item.
    ///
    /// The attachment sheet is dismissed first and the editor raised a beat
    /// later: presenting a full-screen cover from a sheet that is still on its
    /// way out drops the cover entirely.
    func openGalleryMediaEditor(with media: GalleryMedia) {
        showAttachments = false
        let preview = PreviewMediaItem(source: .gallery(media))

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.galleryEditorPreview = preview
        }
    }

    func closeGalleryMediaEditor() {
        galleryEditorPreview = nil
    }

    func postMedia(caption: String?, selectedMedia: [GalleryMedia]) {
        composer?.sendGalleryMedia(caption: caption, selectedMedia: selectedMedia)
    }

    func postCapturedMedia(_ captured: CapturedCameraMedia, caption: String?) {
        composer?.sendCapturedMedia(captured, caption: caption)
    }

    func postEditedMedia(_ result: EditedMediaResult, caption: String?) {
        composer?.sendEditedMedia(result, caption: caption)
    }

    func postDocument(fileURL: URL) {
        composer?.sendDocument(fileURL: fileURL)
    }

    func postContacts(_ contacts: [ContactItem]) {
        composer?.sendContacts(contacts)
    }

    func postLocation(_ location: ChatLocationItem) {
        composer?.sendLocation(location)
    }

    func postPoll(question: String, options: [String], allowsMultipleAnswers: Bool) {
        let sent = composer?.sendPoll(
            question: question,
            options: options,
            allowsMultipleAnswers: allowsMultipleAnswers
        ) ?? false

        if !sent {
            errorMessage = t(ChatTranslationKeys.CHANNELS_POLL_NEEDS_OPTIONS)
        }
    }

    // MARK: - Admins

    @Published private(set) var admins: [ChannelAdmin] = []

    func loadAdmins() async {
        admins = (try? await channelUseCases.manageAdmins.list(channelId: channelId)) ?? []
    }

    func addAdmin(userId: String, userName: String) async {
        do {
            try await channelUseCases.manageAdmins.add(
                channelId: channelId,
                userId: userId,
                userName: userName
            )
            await loadAdmins()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func removeAdmin(userId: String) async {
        do {
            try await channelUseCases.manageAdmins.remove(channelId: channelId, userId: userId)
            await loadAdmins()
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Forwarding

    /// What the picker forwards: the single post the reader long-pressed.
    var messagesToForward: [MessageDataItem] {
        postBeingForwarded.map { [$0] } ?? []
    }

    func beginForwarding(_ post: MessageDataItem) {
        postBeingForwarded = post
    }

    func forward(
        to targets: [ForwardTarget],
        caption: String?,
        statusPoster: (any ForwardStatusPosting)?
    ) async {
        let messages = messagesToForward
        guard !messages.isEmpty else { return }

        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmed?.isEmpty ?? true) ? nil : trimmed

        await forwarding.forward(messages, to: targets, caption: note)

        if targets.contains(where: \.isStatus) {
            await postToStatus(messages, caption: note, poster: statusPoster)
        }

        postBeingForwarded = nil
    }

    /// Posting a forward to your own status — the same mapper the chat room uses.
    private func postToStatus(
        _ messages: [MessageDataItem],
        caption: String?,
        poster: (any ForwardStatusPosting)?
    ) async {
        guard let poster else {
            errorMessage = t(ChatTranslationKeys.FORWARD_STATUS_FAILED)
            return
        }

        var posted = 0
        for message in messages {
            guard let story = ForwardStatusMapper.story(from: message, caption: caption) else { continue }
            await poster.addOwnStatus(story: story)
            posted += 1
        }

        if posted < messages.count {
            errorMessage = t(ChatTranslationKeys.FORWARD_STATUS_FAILED)
        }
    }

    // MARK: - Voice

    func startVoiceRecording() async {
        await voiceRecordingViewModel.startRecording()
    }

    func stopVoiceRecordingAndSend() async {
        let result = await voiceRecordingViewModel.stopRecording()
        await composer?.sendVoice(result: result, attachments: voiceAttachments)
    }

    func cancelVoiceRecording() async {
        _ = await voiceRecordingViewModel.stopRecording()
        voiceAttachments.clear()
    }

    func pauseVoiceRecording() async {
        await voiceRecordingViewModel.pauseRecording()
    }

    func resumeVoiceRecording() async {
        await voiceRecordingViewModel.resumeRecording()
    }

    /// The conversation the sheets act on, once it is known.
    var conversationIdForSheets: String? { conversationId }

    func recentDocuments() async -> [MessageDataItem] {
        guard let conversationId else { return [] }
        return await messagesUseCases.fetchRecentSentDocuments.execute(
            conversationId: conversationId,
            limit: 20
        )
    }



    func react(to post: MessageDataItem, with reaction: Reaction) async {
        guard let conversationId else { return }
        do {
            _ = try await roomUseCases.reactToMessage.execute(
                message: post,
                reaction: reaction,
                conversationId: conversationId
            )
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Clears the unread badge for what is on screen.
    ///
    /// Without this a channel accumulated unread counts nobody could ever clear:
    /// reading a broadcast is still reading it, and the Updates row shows that
    /// count. Own posts are skipped — there is no sense in reporting that you
    /// read yourself.
    private func markRead() async {
        guard let conversationId else { return }
        let currentUserId = CurrentSessionInfo.shared.currentUid
        let unreadFromOthers = posts.filter { $0.senderId != currentUserId }
        guard !unreadFromOthers.isEmpty else { return }

        await roomUseCases.markMessagesAsRead.execute(
            messages: unreadFromOthers,
            conversationId: conversationId
        )
    }

    /// Oldest first, newest at the bottom — the order every room in this app
    /// reads in, and the one the composer sits under. A feed that grows upward
    /// puts the newest post furthest from the keyboard that just wrote it.
    private static func oldestFirst(_ items: [MessageDataItem]) -> [MessageDataItem] {
        var seen = Set<String>()
        return items
            .filter { !$0.isDeleted && seen.insert($0.codeMessage).inserted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private static let pageSize = 30

    /// Makes sure this device has a row for the channel's conversation.
    ///
    /// `MessageModel` has a foreign key onto the conversation table, so a post
    /// written for a conversation this device has never seen is rejected by
    /// SQLite and vanishes. The row normally arrives with the inbox sync — but
    /// the owner of a brand-new channel gets here first, and posting must not
    /// have to wait for a sync that has nothing to report yet.
    private func ensureLocalConversation(conversationId: String, channel: Channel) async {
        await ChannelLocalConversationSync.ensure(
            conversationId: conversationId,
            channel: channel,
            discussionUseCases: discussionUseCases
        )
    }

    // MARK: - Views

    /// Recounts views. Called with the room and after each new post arrives —
    /// receipts land with the sync, not with the message.
    func refreshViewCounts() async {
        guard let conversationId else { return }
        viewCounts = await postViews.viewCounts(conversationId: conversationId)
    }

    func views(of post: MessageDataItem) -> Int {
        viewCounts[post.codeMessage] ?? 0
    }

    // MARK: - Private


    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func message(for error: Error) -> String {
        (error as? ChannelError)?.errorDescription ?? error.localizedDescription
    }
}
