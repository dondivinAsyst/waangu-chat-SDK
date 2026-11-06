import Foundation
import WaanguCoreKit

protocol MessagesRepositoryProtocol {
    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem]
    func fetchRecentSentDocuments(
        conversationId: String,
        senderId: String,
        limit: Int
    ) async throws -> [MessageDataItem]
    func observeMessages(conversationId: String) -> AsyncStream<Result<[MessageDataItem], DatabaseError>>
    func countMediaMessagesWithGroupId(groupId: String) async -> Int
    func updateMessage(message: MessageDataItem) async throws
    func applyReaction(
        messageId: String,
        userId: String,
        userName: String,
        emoji: String,
        removing: Bool
    ) async throws -> [ReactionItem]
    func deleteMessage(messageId: String) async throws
    func deleteMessage(messageId: String, forEveryone: Bool) async throws
}
