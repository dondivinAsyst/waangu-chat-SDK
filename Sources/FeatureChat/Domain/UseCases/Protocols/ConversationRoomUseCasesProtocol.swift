import Foundation
import WaanguCoreKit

// MARK: - Protocols

public protocol ObserveMessagesUseCaseProtocol: Sendable {
    func execute(conversationId: String) -> AsyncStream<Result<[MessageDataItem], DatabaseError>>
}

public protocol ObserveTypingUseCaseProtocol: Sendable {
    func execute(conversationId: String) async throws -> AsyncStream<[TypingUser]>
}

public protocol SendTypingUseCaseProtocol: Sendable {
    func execute(conversationId: String, isTyping: Bool, isRecording: Bool) async
    func stop(conversationId: String) async
}

public protocol LoadMessagesPageUseCaseProtocol: Sendable {
    func execute(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> ChatRoomPaginationResult
}

public protocol SendMessageUseCaseProtocol: Sendable {
    @discardableResult
    func execute(_ request: SendMessageRequest) async -> String?
}

public protocol PublishOutgoingMessageUseCaseProtocol: Sendable {
    func execute(message: MessageDataItem,conversationId:String) async
}

public protocol MarkMessagesAsReadUseCaseProtocol: Sendable {
    func execute(messages: [MessageDataItem], conversationId: String) async
    func republishRead(message: MessageDataItem, conversationId: String) async
}

public protocol PublishDeleteMessageUseCaseProtocol: Sendable {
    func execute(
        codeMessage: String,
        conversationId: String,
        forEveryone: Bool
    ) async
}

public protocol ModifyMessageUseCaseProtocol: Sendable {
    func execute(
        message: MessageDataItem,
        newText: String,
        conversationId: String
    ) async throws
}

public protocol ReactToMessageUseCaseProtocol: Sendable {
    @discardableResult
    func execute(
        message: MessageDataItem,
        reaction: Reaction,
        conversationId: String
    ) async throws -> MessageDataItem

    @discardableResult
    func execute(
        message: MessageDataItem,
        emoji: String,
        conversationId: String
    ) async throws -> MessageDataItem
}

/// Publishes a vote on a poll message.
///
/// The local poll is already updated by the time this runs — the caller writes
/// optimistically so the bar moves on the tap — so this only carries the vote
/// to the server and the outbox.
///
/// `optionIds` is the voter's whole selection, not the option they tapped: an
/// empty array is a retraction, and several are a multiple-choice answer.
public protocol VotePollUseCaseProtocol: Sendable {
    func execute(messageId: String, optionIds: [String], conversationId: String) async
}

/// Carries a live location share: the Redis mapping, the GPS ticks, the stop.
///
/// The anchor message goes out on the ordinary message path before any of this
/// runs — `start` is what makes Realtime accept ticks for the share, and it is
/// deliberately a separate step so a GPS position never republishes a message.
public protocol PublishLiveLocationUseCaseProtocol: Sendable {
    func start(
        shareId: String,
        conversationId: String,
        codeMessage: String,
        durationMinutes: Int,
        expiresAt: Date
    ) async

    func tick(
        shareId: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double?,
        expiresAt: Date,
        bootstrap: (conversationId: String, codeMessage: String)?
    ) async

    func stop(
        shareId: String,
        latitude: Double?,
        longitude: Double?,
        accuracy: Double?
    ) async
}

public protocol ChatRoomSessionUseCaseProtocol: Sendable {
    @MainActor
    func start(conversationId: String, store: ChatRoomMessagesStore) async
    @MainActor
    func stop(store: ChatRoomMessagesStore) async
    @MainActor
    func loadMore(conversationId: String, store: ChatRoomMessagesStore) async
}

public protocol ConversationRoomUseCasesProtocol {
    var observeMessages: ObserveMessagesUseCaseProtocol { get }
    var observeTyping: ObserveTypingUseCaseProtocol { get }
    var sendTyping: SendTypingUseCaseProtocol { get }
    var loadMessagesPage: LoadMessagesPageUseCaseProtocol { get }
    var sendMessage: SendMessageUseCaseProtocol { get }
    var publishOutgoingMessage: PublishOutgoingMessageUseCaseProtocol { get }
    var markMessagesAsRead: MarkMessagesAsReadUseCaseProtocol { get }
    var publishDeleteMessage: PublishDeleteMessageUseCaseProtocol { get }
    var modifyMessage: ModifyMessageUseCaseProtocol { get }
    var reactToMessage: ReactToMessageUseCaseProtocol { get }
    var votePoll: VotePollUseCaseProtocol { get }
    var publishLiveLocation: PublishLiveLocationUseCaseProtocol { get }
    var session: ChatRoomSessionUseCaseProtocol { get }

    // MARK: - Realtime Health (monitoring)

    func observeRealtimeConnectionState() -> AsyncStream<RealtimeConnectionState>
    func realtimeConnectionState() async -> RealtimeConnectionState
    func isInboxSubscribed() async -> Bool
    func subscriptionDiagnostics() async -> [RealtimeSubscriptionDiagnostic]

    // MARK: - Outbox Health (monitoring)

    /// Both outbound queues — persisted outbox and buffered MQTT publishes —
    /// as they stand right now. Read-only; sends nothing.
    func outboxDiagnostics() async throws -> ChatOutboxSnapshot
}

// MARK: - Request / Result types

public struct SendMessageRequest: Sendable {
    let content: MessageContent
    let type: MessageTypeProps
    let conversationId: String
    let receiver: UserRoom?
    /// What the conversation is. `isGroup` is derived from it, never passed in:
    /// a boolean cannot tell a broadcast from a group, and the store believes
    /// what it is told.
    let kind: ConversationKind
    let reply: MessageReply?
    let recipientId: String?
    let messageCode: String?
    /// Marks the message as forwarded, all the way to the local row and the wire
    /// DTO. Without it a forward is indistinguishable from an original message
    /// and the "Forwarded" label never shows on either side.
    let forwarded: Bool
    /// Opened once on each side, then only an "Opened" line remains.
    let viewOnce: Bool

    /// `isGroup` on the wire, derived from the kind.
    var isGroup: Bool { kind.travelsAsGroup }

    init(
        content: MessageContent,
        type: MessageTypeProps,
        conversationId: String,
        receiver: UserRoom?,
        kind: ConversationKind,
        reply: MessageReply? = nil,
        recipientId: String? = nil,
        messageCode: String? = nil,
        forwarded: Bool = false,
        viewOnce: Bool = false
    ) {
        self.content = content
        self.type = type
        self.conversationId = conversationId
        self.receiver = receiver
        self.kind = kind
        self.reply = reply
        self.recipientId = recipientId
        self.messageCode = messageCode
        self.forwarded = forwarded
        self.viewOnce = viewOnce
    }
}

public struct ChatRoomPaginationResult: Sendable {
    let messages: [MessageDataItem]
    let allMediaMessages: [MessageDataItem]
    let oldestLoadedDate: Date?
    let hasMore: Bool

    init(
        messages: [MessageDataItem],
        allMediaMessages: [MessageDataItem],
        oldestLoadedDate: Date?,
        hasMore: Bool
    ) {
        self.messages = messages
        self.allMediaMessages = allMediaMessages
        self.oldestLoadedDate = oldestLoadedDate
        self.hasMore = hasMore
    }
}
