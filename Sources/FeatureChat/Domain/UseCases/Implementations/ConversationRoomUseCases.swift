import Foundation
import WaanguCoreKit
import UIKit

// MARK: - Observe Messages

struct ObserveMessagesUseCase: ObserveMessagesUseCaseProtocol {
    private let repository: MessagesRepositoryProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.repository = repository
    }

    func execute(conversationId: String) -> AsyncStream<Result<[MessageDataItem], DatabaseError>> {
        repository.observeMessages(conversationId: conversationId)
    }
}

// MARK: - Observe Typing

/// Reads one conversation's slice of the session-wide typing feed.
///
/// The MQTT subscription itself belongs to `PresenceRepository` and is started
/// once per session by `ChatPresenceLifecycle`; a room opening is only a new
/// reader of `TypingStore`, not a new subscription.
struct ObserveTypingUseCase: ObserveTypingUseCaseProtocol {
    func execute(conversationId: String) async throws -> AsyncStream<[TypingUser]> {
        await TypingStore.shared.stream(for: conversationId)
    }
}

// MARK: - Send Typing

/// Publishes typing indicators, throttled per conversation.
///
/// `execute` is called on every keystroke, so it must not publish every time:
/// one MQTT round-trip per character floods the broker, and the echo comes
/// straight back to us on the same topic. Only the first keystroke of a burst
/// goes out; the rest are suppressed until `throttleInterval` has elapsed.
///
/// Leading edge, not trailing: the peer sees "typing…" on the first character
/// rather than after a delay. Re-publishing every interval while the burst
/// continues keeps the peer's indicator from expiring on its own timeout.
actor SendTypingUseCase: SendTypingUseCaseProtocol {
    private let repository: PresenceRepositoryProtocol
    private let throttleInterval: TimeInterval
    private let now: @Sendable () -> Date

    /// Last publish per conversation, with the type that was sent.
    private var lastPublish: [String: (at: Date, type: TypingPayloadType)] = [:]

    init(
        repository: PresenceRepositoryProtocol,
        throttleInterval: TimeInterval = 3,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.throttleInterval = throttleInterval
        self.now = now
    }

    func execute(conversationId: String, isTyping: Bool, isRecording: Bool) async {
        // Composer emptied or recording finished — the peer's indicator expires
        // on its own timeout. Drop the throttle so resuming publishes at once.
        guard isTyping || isRecording else {
            lastPublish.removeValue(forKey: conversationId)
            return
        }

        let type: TypingPayloadType = isRecording ? .audio : .text
        let timestamp = now()

        // Switching between text and voice is a state change the peer must see
        // immediately, so it bypasses the throttle window.
        if let last = lastPublish[conversationId],
           last.type == type,
           timestamp.timeIntervalSince(last.at) < throttleInterval {
            return
        }

        lastPublish[conversationId] = (at: timestamp, type: type)
        await repository.sendTyping(conversationId: conversationId, type: type)
    }

    func stop(conversationId: String) async {
        lastPublish.removeValue(forKey: conversationId)
    }
}

// MARK: - Load Messages Page

struct LoadMessagesPageUseCase: LoadMessagesPageUseCaseProtocol {
    private let discussionsRepository: DiscussionRepositoryProtocol

    init(discussionsRepository: DiscussionRepositoryProtocol) {
        self.discussionsRepository = discussionsRepository
    }

    func execute(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> ChatRoomPaginationResult {
        let raw = try await discussionsRepository.fetchMessagesWithPagination(
            conversationId: conversationId,
            before: cursor,
            pageSize: pageSize
        )
        let sorted = raw.sorted { $0.createdAt < $1.createdAt }
        let media = sorted.filter { ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce }
        return ChatRoomPaginationResult(
            messages: sorted,
            allMediaMessages: media,
            oldestLoadedDate: sorted.first?.createdAt,
            hasMore: raw.count >= pageSize
        )
    }
}

// MARK: - Send Message

struct SendMessageUseCase: SendMessageUseCaseProtocol {
    private let discussionRepository: DiscussionRepositoryProtocol
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol

    init(
        discussionRepository: DiscussionRepositoryProtocol,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) {
        self.discussionRepository = discussionRepository
        self.outbox = outbox
        self.realtime = realtime
    }

    func execute(_ request: SendMessageRequest) async -> String? {
        var content = request.content
        let code = request.messageCode ?? OutgoingMessageBuilder.newCode()

        if request.type == .IMAGE {
            if let error = OutgoingMessageBuilder.validateAndCacheImage(content: content, code: code) {
                #if DEBUG
                print("[SendMessage] \(error)")
                #endif
                return nil
            }
        }

        // The stored group id, not the conversation id standing in for it. They are
        // the same string today, but the outbound message has a field for each and
        // the group endpoints key on the group one.
        let outboundGroupId = request.isGroup
            ? await discussionRepository.outboundGroupId(for: request.conversationId)
            : nil

        var message = OutgoingMessageBuilder.buildOutgoingMessage(
            content: content,
            type: request.type,
            groupId: outboundGroupId,
            reply: request.reply,
            code: code,
            receiverId: request.recipientId ?? "",
            forwarded: request.forwarded,
            viewOnce: request.viewOnce
        )

        if request.type == .AUDIO || request.type == .VOICE {
            switch OutgoingMessageBuilder.prepareAudio(content: content, baseMessage: message) {
            case .ready(let updated, _):
                message = updated
            case .failed(let error):
                #if DEBUG
                print("[SendMessage] \(error)")
                #endif
                return nil
            }
        }

        let discussion = DiscussionChatItem(
            lastMessage: message,
            conversationId: request.conversationId,
            contact: DiscussionContactBuilder.contactChannel(
                from: request.receiver,
                kind: request.kind
            )
        )

        do {
            try await discussionRepository.saveDiscussion(discussion)
        } catch {
            #if DEBUG
            print("[SendMessage] Failed to save: \(error)")
            #endif
            return nil
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .outgoingMessageLocallySaved,
                object: OutgoingMessageLocallySavedEvent(
                    conversationId: request.conversationId,
                    message: message
                )
            )
            NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
        }

        if OutgoingMessageBuilder.requiresUploadBeforePublish(message) {
            #if DEBUG
            print("[SendMessage] Deferred network publish until upload completes: \(message.codeMessage)")
            #endif
            return message.codeMessage
        }

        // Local row stays on `request.conversationId`; the wire must use the
        // linked server id once MESSAGE_SENT ACK has set `serverId`.
        let publishConversationId = await discussionRepository.outboundConversationId(
            for: request.conversationId
        )
        if request.isGroup {
            message.groupId = publishConversationId
        }

        await OutgoingMessagePublisher.publish(
            message: message,
            conversationId: publishConversationId,
            recipientId: request.recipientId,
            outbox: outbox,
            realtime: realtime
        )

        return message.codeMessage
    }
}

struct PublishOutgoingMessageUseCase: PublishOutgoingMessageUseCaseProtocol {
    private let discussionRepository: DiscussionRepositoryProtocol
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol

    init(
        discussionRepository: DiscussionRepositoryProtocol,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) {
        self.discussionRepository = discussionRepository
        self.outbox = outbox
        self.realtime = realtime
    }

    func execute(message: MessageDataItem,conversationId:String) async {
        let normalized = OutboundMessageFieldNormalizer.ensuringSenderFields(message)
        guard !OutgoingMessageBuilder.requiresUploadBeforePublish(normalized) else {
            #if DEBUG
            print("[PublishOutgoingMessage] Skipped — upload still pending for \(normalized.codeMessage)")
            #endif
            return
        }

        let publishConversationId = await discussionRepository.outboundConversationId(
            for: conversationId
        )
        var toPublish = normalized
        if let groupId = toPublish.groupId, !groupId.isEmpty {
            toPublish.groupId = publishConversationId
        }

        await OutgoingMessagePublisher.publish(
            message: toPublish,
            conversationId: publishConversationId,
            recipientId: normalized.receiverId.isEmpty ? nil : normalized.receiverId,
            outbox: outbox,
            realtime: realtime
        )
    }
}

struct MarkMessagesAsReadUseCase: MarkMessagesAsReadUseCaseProtocol {
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol
    private let discussionRepository: DiscussionRepositoryProtocol
    private let currentUserId: @Sendable () -> String

    init(
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol,
        discussionRepository: DiscussionRepositoryProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid }
    ) {
        self.outbox = outbox
        self.realtime = realtime
        self.discussionRepository = discussionRepository
        self.currentUserId = currentUserId
    }

    func execute(messages: [MessageDataItem], conversationId: String) async {
        let userId = currentUserId()
        guard !userId.isEmpty else { return }

        let unreadIncoming = messages.filter {
            $0.senderId != userId
                && $0.status != .SEEN
                && !$0.codeMessage.isEmpty
                && !$0.typeMessage.isSystemRecord
        }

        let publishConversationId = await discussionRepository.outboundConversationId(
            for: conversationId
        )

        for message in unreadIncoming {
            await MarkAsReadPublisher.publish(
                codeMessage: message.codeMessage,
                userId: userId,
                conversationId: publishConversationId,
                outbox: outbox,
                realtime: realtime
            )
        }

        let isViewingConversation = ActiveChatSessionStore.shared.isViewing(
            conversationId: conversationId
        )
        guard !unreadIncoming.isEmpty || isViewingConversation else { return }

        try? await discussionRepository.clearUnreadCount(conversationId: conversationId)
    }

    func republishRead(message: MessageDataItem, conversationId: String) async {
        let userId = currentUserId()
        let codeMessage = message.codeMessage
        guard !userId.isEmpty, !codeMessage.isEmpty, !message.typeMessage.isSystemRecord else {
            return
        }

        let publishConversationId = await discussionRepository.outboundConversationId(
            for: conversationId
        )

        await MarkAsReadPublisher.publish(
            codeMessage: codeMessage,
            userId: userId,
            conversationId: publishConversationId,
            outbox: outbox,
            realtime: realtime
        )

        if ActiveChatSessionStore.shared.isViewing(conversationId: conversationId) {
            try? await discussionRepository.clearUnreadCount(conversationId: conversationId)
        }
    }
}

struct PublishDeleteMessageUseCase: PublishDeleteMessageUseCaseProtocol {
    private let discussionRepository: DiscussionRepositoryProtocol
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol
    private let currentUserId: @Sendable () -> String

    init(
        discussionRepository: DiscussionRepositoryProtocol,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid }
    ) {
        self.discussionRepository = discussionRepository
        self.outbox = outbox
        self.realtime = realtime
        self.currentUserId = currentUserId
    }

    func execute(
        codeMessage: String,
        conversationId: String,
        forEveryone: Bool
    ) async {
        let publishConversationId = await discussionRepository.outboundConversationId(
            for: conversationId
        )
        await DeleteMessagePublisher.publish(
            codeMessage: codeMessage,
            conversationId: publishConversationId,
            forEveryone: forEveryone,
            senderId: currentUserId(),
            outbox: outbox,
            realtime: realtime
        )
    }
}

struct ModifyMessageUseCase: ModifyMessageUseCaseProtocol {
    private let messagesRepository: MessagesRepositoryProtocol
    private let discussionRepository: DiscussionRepositoryProtocol
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol
    private let currentUserId: @Sendable () -> String

    init(
        messagesRepository: MessagesRepositoryProtocol,
        discussionRepository: DiscussionRepositoryProtocol,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid }
    ) {
        self.messagesRepository = messagesRepository
        self.discussionRepository = discussionRepository
        self.outbox = outbox
        self.realtime = realtime
        self.currentUserId = currentUserId
    }

    func execute(
        message: MessageDataItem,
        newText: String,
        conversationId: String
    ) async throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard message.isSentByMe, message.typeMessage == .TEXT, !message.isDeleted else { return }
        guard trimmed != message.message.text else { return }

        var updated = message
        updated.message.text = trimmed
        // Local UI should follow the same optimistic send lifecycle as new messages.
        updated.status = .PENDING

        try await messagesRepository.updateMessage(message: updated)

        let publishConversationId = await discussionRepository.outboundConversationId(
            for: conversationId
        )

        await ModifyMessagePublisher.publish(
            codeMessage: message.codeMessage,
            conversationId: publishConversationId,
            content: MessageContentWireCodec.encode(from: updated),
            status: MessageStatus.MODIFY.rawValue,
            senderId: currentUserId(),
            outbox: outbox,
            realtime: realtime
        )
    }
}

struct ReactToMessageUseCase: ReactToMessageUseCaseProtocol {
    private let messagesRepository: MessagesRepositoryProtocol
    private let discussionRepository: DiscussionRepositoryProtocol
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol
    private let currentUserId: @Sendable () -> String

    init(
        messagesRepository: MessagesRepositoryProtocol,
        discussionRepository: DiscussionRepositoryProtocol,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid }
    ) {
        self.messagesRepository = messagesRepository
        self.discussionRepository = discussionRepository
        self.outbox = outbox
        self.realtime = realtime
        self.currentUserId = currentUserId
    }

    @discardableResult
    func execute(
        message: MessageDataItem,
        reaction: Reaction,
        conversationId: String
    ) async throws -> MessageDataItem {
        guard reaction != .more else { return message }
        return try await execute(message: message, emoji: reaction.emoji, conversationId: conversationId)
    }

    @discardableResult
    func execute(
        message: MessageDataItem,
        emoji: String,
        conversationId: String
    ) async throws -> MessageDataItem {
        let userId = currentUserId()
        guard !userId.isEmpty, !emoji.isEmpty else { return message }

        let existing = message.reactions?.first { $0.userId == userId }
        let removing = existing?.reaction == emoji

        let reactions = try await messagesRepository.applyReaction(
            messageId: message.codeMessage,
            userId: userId,
            userName: "",
            emoji: emoji,
            removing: removing
        )

        var updated = message
        updated.reactions = reactions.isEmpty ? nil : reactions

        let publishConversationId = await discussionRepository.outboundConversationId(
            for: conversationId
        )

        #if DEBUG
        print(
            "[Reaction] outbound remove=\(removing) codeMessage=\(message.codeMessage) localConversation=\(conversationId) publishConversation=\(publishConversationId) reactor=\(userId) emoji=\(emoji)"
        )
        #endif

        await ReactionMessagePublisher.publish(
            codeMessage: message.codeMessage,
            conversationId: publishConversationId,
            reaction: emoji,
            userId: userId,
            removing: removing,
            outbox: outbox,
            realtime: realtime
        )

        return updated
    }
}

enum DiscussionContactBuilder {
    /// The kind travels all the way to the stored row: `isChannel` is what stops
    /// the store writing a broadcast as a group.
    static func contactChannel(from receiver: UserRoom?, kind: ConversationKind) -> ContactChannel {
        ContactChannel(
            userName: receiver?.name ?? "",
            phone: receiver?.phone ?? "",
            image: receiver?.avatar ?? "",
            isBlocked: receiver?.isBlocked ?? false,
            isGroup: kind.travelsAsGroup,
            isChannel: kind == .channel,
            id: receiver?.idContact ?? "",
            userId: receiver?.userId ?? ""
        )
    }
}

// MARK: - Vote Poll

struct VotePollUseCase: VotePollUseCaseProtocol {
    private let outbox: any ChatOutboxEnqueuing
    private let realtime: any RealtimeClientProtocol
    private let currentUserId: @Sendable () -> String

    init(
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol,
        currentUserId: @escaping @Sendable () -> String
    ) {
        self.outbox = outbox
        self.realtime = realtime
        self.currentUserId = currentUserId
    }

    func execute(messageId: String, optionIds: [String], conversationId: String) async {
        await PollMessagePublisher.publishVote(
            codeMessage: messageId,
            conversationId: conversationId,
            optionIds: optionIds,
            userId: currentUserId(),
            outbox: outbox,
            realtime: realtime
        )
    }
}

// MARK: - Live location

struct PublishLiveLocationUseCase: PublishLiveLocationUseCaseProtocol {
    private let realtime: any RealtimeClientProtocol
    private let currentUserId: @Sendable () -> String

    init(
        realtime: any RealtimeClientProtocol,
        currentUserId: @escaping @Sendable () -> String
    ) {
        self.realtime = realtime
        self.currentUserId = currentUserId
    }

    func start(
        shareId: String,
        conversationId: String,
        codeMessage: String,
        durationMinutes: Int,
        expiresAt: Date
    ) async {
        await LiveLocationPublisher.publishStart(
            shareId: shareId,
            conversationId: conversationId,
            codeMessage: codeMessage,
            durationMinutes: durationMinutes,
            expiresAt: expiresAt,
            userId: currentUserId(),
            realtime: realtime
        )
    }

    func tick(
        shareId: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double?,
        expiresAt: Date,
        bootstrap: (conversationId: String, codeMessage: String)?
    ) async {
        await LiveLocationPublisher.publishTick(
            shareId: shareId,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            expiresAt: expiresAt,
            bootstrap: bootstrap,
            userId: currentUserId(),
            realtime: realtime
        )
    }

    func stop(
        shareId: String,
        latitude: Double?,
        longitude: Double?,
        accuracy: Double?
    ) async {
        await LiveLocationPublisher.publishStop(
            shareId: shareId,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            userId: currentUserId(),
            realtime: realtime
        )
    }
}

// MARK: - Session

final class ChatRoomSessionUseCase: ChatRoomSessionUseCaseProtocol {
    private let observeMessages: ObserveMessagesUseCaseProtocol
    private let observeTyping: ObserveTypingUseCaseProtocol
    private let loadMessagesPage: LoadMessagesPageUseCaseProtocol
    private let discussionRepository: DiscussionRepositoryProtocol
    private let presenceRepository: PresenceRepositoryProtocol
    private let metricsSink: any ChatMetricsSink
    private var tasks: [Task<Void, Never>] = []

    init(
        observeMessages: ObserveMessagesUseCaseProtocol,
        observeTyping: ObserveTypingUseCaseProtocol,
        loadMessagesPage: LoadMessagesPageUseCaseProtocol,
        discussionRepository: DiscussionRepositoryProtocol,
        presenceRepository: PresenceRepositoryProtocol,
        metricsSink: any ChatMetricsSink = NoChatMetrics()
    ) {
        self.observeMessages = observeMessages
        self.observeTyping = observeTyping
        self.loadMessagesPage = loadMessagesPage
        self.discussionRepository = discussionRepository
        self.presenceRepository = presenceRepository
        self.metricsSink = metricsSink
    }

    @MainActor
    func start(conversationId: String, store: ChatRoomMessagesStore) async {
        // Plan SDK, étape 1.13 : de l'appel à la première page affichable. Le travail de
        // `stop` et l'effacement du compteur de non-lus en font partie, c'est le délai vécu.
        let opening = ContinuousClock.now
        await stop(store: store)

        try? await discussionRepository.clearUnreadCount(conversationId: conversationId)

        do {
            let page = try await loadMessagesPage.execute(
                conversationId: conversationId,
                before: nil,
                pageSize: ChatRoomMessagesStore.defaultPageSize
            )
            await store.applyInitialPage(page)
            metricsSink.record(ChatMetric(name: ChatMetricName.conversationOpen,
                                          durationMs: ChatMetric.elapsedMs(since: opening),
                                          attributes: ["result": "ok"]))
        } catch {
            metricsSink.record(ChatMetric(name: ChatMetricName.conversationOpen,
                                          durationMs: ChatMetric.elapsedMs(since: opening),
                                          attributes: ["result": "failed"]))
            #if DEBUG
            print("[ChatRoomSession] Initial load failed: \(error)")
            #endif
        }

        tasks.append(Task {
            for await result in observeMessages.execute(conversationId: conversationId) {
                if case .success(let items) = result {
                    await store.applyObservation(items)
                }
            }
        })

        tasks.append(Task {
            guard let stream = try? await observeTyping.execute(conversationId: conversationId) else { return }
            for await users in stream {
                await store.applyTyping(users)
            }
        })
    }

    @MainActor
    func stop(store: ChatRoomMessagesStore) async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        await presenceRepository.cleanup()
        store.resetTyping()
    }

    @MainActor
    func loadMore(conversationId: String, store: ChatRoomMessagesStore) async {
        guard store.hasMore, let cursor = store.oldestLoadedDate else { return }
        do {
            let page = try await loadMessagesPage.execute(
                conversationId: conversationId,
                before: cursor,
                pageSize: ChatRoomMessagesStore.defaultPageSize
            )
            await store.applyPagination(page)
        } catch {
            #if DEBUG
            print("[ChatRoomSession] Load more failed: \(error)")
            #endif
        }
    }
}

// MARK: - Container

final class ConversationRoomUseCases: ConversationRoomUseCasesProtocol {
    public let observeMessages: ObserveMessagesUseCaseProtocol
    public let observeTyping: ObserveTypingUseCaseProtocol
    public let sendTyping: SendTypingUseCaseProtocol
    public let loadMessagesPage: LoadMessagesPageUseCaseProtocol
    public let sendMessage: SendMessageUseCaseProtocol
    public let publishOutgoingMessage: PublishOutgoingMessageUseCaseProtocol
    public let markMessagesAsRead: MarkMessagesAsReadUseCaseProtocol
    public let publishDeleteMessage: PublishDeleteMessageUseCaseProtocol
    public let modifyMessage: ModifyMessageUseCaseProtocol
    public let reactToMessage: ReactToMessageUseCaseProtocol
    public let votePoll: VotePollUseCaseProtocol
    public let publishLiveLocation: PublishLiveLocationUseCaseProtocol
    public let session: ChatRoomSessionUseCaseProtocol

    private let realtime: any RealtimeClientProtocol
    private let outboxInspector: any ChatOutboxInspecting
    private let currentUserId: @Sendable () -> String

    init(
        messagesRepository: MessagesRepositoryProtocol,
        discussionRepository: DiscussionRepositoryProtocol,
        presenceRepository: PresenceRepositoryProtocol,
        outbox: any ChatOutboxEnqueuing,
        outboxInspector: any ChatOutboxInspecting,
        realtime: any RealtimeClientProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid },
        metricsSink: any ChatMetricsSink = NoChatMetrics()
    ) {
        self.realtime = realtime
        self.outboxInspector = outboxInspector
        self.currentUserId = currentUserId
        self.observeMessages = ObserveMessagesUseCase(repository: messagesRepository)
        self.observeTyping = ObserveTypingUseCase()
        self.sendTyping = SendTypingUseCase(repository: presenceRepository)
        self.loadMessagesPage = LoadMessagesPageUseCase(discussionsRepository: discussionRepository)
        self.sendMessage = SendMessageUseCase(
            discussionRepository: discussionRepository,
            outbox: outbox,
            realtime: realtime
        )
        self.publishOutgoingMessage = PublishOutgoingMessageUseCase(
            discussionRepository: discussionRepository,
            outbox: outbox,
            realtime: realtime
        )
        self.markMessagesAsRead = MarkMessagesAsReadUseCase(
            outbox: outbox,
            realtime: realtime,
            discussionRepository: discussionRepository,
            currentUserId: currentUserId
        )
        self.publishDeleteMessage = PublishDeleteMessageUseCase(
            discussionRepository: discussionRepository,
            outbox: outbox,
            realtime: realtime,
            currentUserId: currentUserId
        )
        self.modifyMessage = ModifyMessageUseCase(
            messagesRepository: messagesRepository,
            discussionRepository: discussionRepository,
            outbox: outbox,
            realtime: realtime,
            currentUserId: currentUserId
        )
        self.reactToMessage = ReactToMessageUseCase(
            messagesRepository: messagesRepository,
            discussionRepository: discussionRepository,
            outbox: outbox,
            realtime: realtime,
            currentUserId: currentUserId
        )
        self.votePoll = VotePollUseCase(
            outbox: outbox,
            realtime: realtime,
            currentUserId: currentUserId
        )
        self.publishLiveLocation = PublishLiveLocationUseCase(
            realtime: realtime,
            currentUserId: currentUserId
        )
        self.session = ChatRoomSessionUseCase(
            observeMessages: observeMessages,
            observeTyping: observeTyping,
            loadMessagesPage: loadMessagesPage,
            discussionRepository: discussionRepository,
            presenceRepository: presenceRepository,
            metricsSink: metricsSink
        )
    }

    // MARK: - Realtime Health (monitoring)

    func observeRealtimeConnectionState() -> AsyncStream<RealtimeConnectionState> {
        realtime.observeConnectionState()
    }

    func realtimeConnectionState() async -> RealtimeConnectionState {
        await realtime.connectionState
    }

    /// `true` si on est toujours abonné au topic d'inbox de l'utilisateur courant
    /// (`waangu-chat/{userId}`), là où arrivent les messages entrants.
    func isInboxSubscribed() async -> Bool {
        let userId = currentUserId()
        guard !userId.isEmpty else { return false }
        return await realtime.isSubscribed(to: ChatMQTTTopics.userInbox(userId: userId))
    }

    func subscriptionDiagnostics() async -> [RealtimeSubscriptionDiagnostic] {
        await realtime.subscriptionDiagnostics()
    }

    // MARK: - Outbox Health (monitoring)

    func outboxDiagnostics() async throws -> ChatOutboxSnapshot {
        try await outboxInspector.snapshot()
    }
}
