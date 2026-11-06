import Foundation
import WaanguCoreKit
@testable import WaanguFeatureChat

// MARK: - Discussions

final class FakeDiscussionUseCases: DiscussionUseCasesProtocol {
    let list = FakeGetDiscussions()
    let messages = FakeGetDiscussionMessages()
    let creator = FakeCreateDiscussion()

    var getDiscussions: GetDiscussionUseCaseProtocol { list }
    var createDiscussion: CreateDiscussionUseCaseProtocol { creator }
    var getMessages: GetDiscussionMessagesUseCaseProtocol { messages }
    var getMessagesWithPagination: GetDiscussionMessagesWithPaginationUseCaseProtocol { FakeUnusedDiscussionPieces() }
    var updateDiscussionSetting: UpdateDiscussionSettingUseCaseProtocol { FakeUnusedDiscussionPieces() }
    var deleteDiscussion: DeleteDiscussionUseCaseProtocol { FakeUnusedDiscussionPieces() }
    var deleteAllDiscussionMessages: DeleteAllDiscussionMessagesUseCaseProtocol { FakeUnusedDiscussionPieces() }
    var draft: DiscussionDraftUseCaseProtocol { FakeUnusedDiscussionPieces() }
}

final class FakeGetDiscussions: GetDiscussionUseCaseProtocol {
    var items: [DiscussionChatItem] = []
    var error: Error?
    func execute() async throws -> [DiscussionChatItem]? {
        if let error { throw error }
        return items
    }
}

final class FakeGetDiscussionMessages: GetDiscussionMessagesUseCaseProtocol {
    var byConversation: [String: [MessageDataItem]] = [:]
    func execute(conversationId: String) async throws -> [MessageDataItem]? {
        byConversation[conversationId] ?? []
    }
}

final class FakeCreateDiscussion: CreateDiscussionUseCaseProtocol {
    private(set) var created: [DiscussionChatItem] = []
    func execute(discussion: DiscussionChatItem) async throws {
        created.append(discussion)
    }
}

struct FakeUnusedDiscussionPieces: GetDiscussionMessagesWithPaginationUseCaseProtocol,
    UpdateDiscussionSettingUseCaseProtocol, DeleteDiscussionUseCaseProtocol,
    DeleteAllDiscussionMessagesUseCaseProtocol, DiscussionDraftUseCaseProtocol {
    func execute(conversationId: String, before cursor: Date?, pageSize: Int) async throws -> [MessageDataItem]? { [] }
    func execute(discussion: DiscussionChatItem) async throws {}
    func execute(converationId: String) async throws {}
    func save(conversationId: String, text: String) async throws {}
    func fetch(conversationId: String) async throws -> String? { nil }
}

// MARK: - Messages

struct FakeMessagesUseCases: MessagesUseCasesProtocol, GetMessagesUseCaseProtocol,
    CountMediaMessagesWithSameGroupIdUseCaseProtocol, UpdateMessagesUseCaseProtocol,
    DeleteMessagesUseCaseProtocol, FetchRecentSentDocumentsUseCaseProtocol {
    var getMessages: GetMessagesUseCaseProtocol { self }
    var countMediaMessagesWithSameGroupId: CountMediaMessagesWithSameGroupIdUseCaseProtocol { self }
    var updateMessages: UpdateMessagesUseCaseProtocol { self }
    var deleteMessages: DeleteMessagesUseCaseProtocol { self }
    var fetchRecentSentDocuments: FetchRecentSentDocumentsUseCaseProtocol { self }

    func execute(conversationId: String) async throws -> [MessageDataItem]? { [] }
    func execute(groupId: String) async -> Int? { nil }
    func execute(message: MessageDataItem) async throws {}
    func execute(messageId: String) async throws {}
    func execute(messageId: String, forEveryone: Bool) async throws {}
    func execute(conversationId: String, limit: Int) async -> [MessageDataItem] { [] }
}

/// Records every publication. Called from an actor, hence the lock.
final class FakePublishOutgoingMessage: PublishOutgoingMessageUseCaseProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _published: [(codeMessage: String, conversationId: String)] = []
    private var _messages: [MessageDataItem] = []

    /// Messages as they went out — to inspect the payload the receiver gets.
    var messages: [MessageDataItem] {
        lock.lock(); defer { lock.unlock() }
        return _messages
    }

    var published: [(codeMessage: String, conversationId: String)] {
        lock.lock(); defer { lock.unlock() }
        return _published
    }

    func execute(message: MessageDataItem, conversationId: String) async {
        lock.lock(); defer { lock.unlock() }
        _published.append((message.codeMessage, conversationId))
        _messages.append(message)
    }
}

/// No local state, no server projection: publications stay pending cards.
struct FakeFinancialObjects: FinancialObjectUseCasesProtocol {
    /// What the server answers to a read. `nil` ⇒ the read fails.
    var served: FinancialCardPayload? = nil

    func current(for reference: FinancialReference) async -> FinancialCardPayload? { nil }
    func refresh(_ reference: FinancialReference) async -> Result<FinancialCardPayload, FinanceError> {
        served.map { .success($0) } ?? .failure(.capabilityUnavailable)
    }
    func apply(_ payload: FinancialCardPayload) async -> Bool { false }
    func recordSubmission(_ payload: FinancialCardPayload) async {}
    func discardSubmission(_ reference: FinancialReference) async {}
    func reconcilePending() async {}
    func restoreHydrated() async {}
    func pendingReconciliation() async -> [FinancialCardPayload] { [] }
    func purge() async {}
}

// MARK: - Publisher

/// Stands in for `PublishFinanceMessageUseCase` where only the target matters.
final class FakePublishFinanceMessage: PublishFinanceMessageUseCaseProtocol, @unchecked Sendable {
    private(set) var targets: [FinanceMessageTarget] = []
    /// Notes received, in publication order.
    private(set) var notes: [String?] = []
    /// Receivers whose publication fails.
    var failingReceivers: Set<String> = []

    func execute(
        _ reference: FinancialReference,
        note: String?,
        to target: FinanceMessageTarget,
        onLocallySaved: (([MessageDataItem]) async -> Void)?
    ) async throws -> MessageDataItem {
        if failingReceivers.contains(target.receiverUserId) {
            throw PublishFinanceMessageError.storageFailed("forced")
        }
        targets.append(target)
        notes.append(note)
        return FinanceConversationMessage.make(
            reference: reference, note: note, payload: nil,
            groupID: nil, receiverID: target.receiverUserId
        )
    }
}

// MARK: - Fabriques

enum MessagingFixtures {

    static func contact(
        userId: String,
        name: String = "Someone",
        phone: String
    ) -> UserContactProps {
        UserContactProps(
            idContact: "contact-\(userId)", userId: userId, name: name,
            avatar: nil, phone: phone, description: "", isBlocked: false
        )
    }

    static func directDiscussion(conversationId: String, phone: String) -> DiscussionChatItem {
        DiscussionChatItem(
            lastMessage: FinanceConversationMessage.make(
                reference: FinanceFixtures.reference(), payload: nil, groupID: nil, receiverID: "peer"
            ),
            conversationId: conversationId,
            contact: ContactChannel(phone: phone, isBlocked: false, isGroup: false)
        )
    }
}
