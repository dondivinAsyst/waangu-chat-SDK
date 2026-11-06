import Foundation
import WaanguCoreKit

class MessageRepository: MessagesRepositoryProtocol {

    private let localDataSource: LocalMessageDataSourceProtocol

    init(localDataSource: LocalMessageDataSourceProtocol) {
        self.localDataSource = localDataSource
    }

    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem] {
        try await localDataSource.fetchMessages(conversationId)
    }

    func fetchRecentSentDocuments(
        conversationId: String,
        senderId: String,
        limit: Int
    ) async throws -> [MessageDataItem] {
        try await localDataSource.fetchRecentSentDocuments(
            conversationId: conversationId,
            senderId: senderId,
            limit: limit
        )
    }

    func observeMessages(conversationId: String) -> AsyncStream<Result<[MessageDataItem], DatabaseError>> {
        localDataSource.observeMessages(conversationId)
    }

    func countMediaMessagesWithGroupId(groupId: String) async -> Int {
        await localDataSource.countMediaMessages(groupId: groupId)
    }

    func updateMessage(message: MessageDataItem) async throws {
        try await localDataSource.updateMessage(message)
    }

    func applyReaction(
        messageId: String,
        userId: String,
        userName: String,
        emoji: String,
        removing: Bool
    ) async throws -> [ReactionItem] {
        try await localDataSource.applyReaction(
            messageId: messageId,
            userId: userId,
            userName: userName,
            emoji: emoji,
            removing: removing
        )
    }

    func deleteMessage(messageId: String) async throws {
        try await deleteMessage(messageId: messageId, forEveryone: false)
    }

    func deleteMessage(messageId: String, forEveryone: Bool) async throws {
        try await localDataSource.deleteMessage(messageId: messageId, forEveryone: forEveryone)
    }
}
