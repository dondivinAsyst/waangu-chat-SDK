
import Foundation

public protocol GetDiscussionUseCaseProtocol {
    func execute() async throws -> [DiscussionChatItem]?
}
public protocol GetDiscussionMessagesUseCaseProtocol {
    func execute(conversationId: String) async throws -> [MessageDataItem]?
}
public protocol GetDiscussionMessagesWithPaginationUseCaseProtocol {
    func execute(conversationId: String,
                   before cursor: Date?,
                   pageSize: Int) async throws -> [MessageDataItem]?
}
public protocol CreateDiscussionUseCaseProtocol {
    func execute(discussion: DiscussionChatItem) async throws
}
public protocol UpdateDiscussionSettingUseCaseProtocol {
    func execute(discussion: DiscussionChatItem) async throws
}
public protocol DeleteDiscussionUseCaseProtocol{
    func execute(converationId: String) async throws
}
public protocol DeleteAllDiscussionMessagesUseCaseProtocol{
    func execute(converationId: String) async throws
}
/// Persists / restores the text left in a conversation's composer.
public protocol DiscussionDraftUseCaseProtocol {
    func save(conversationId: String, text: String) async throws
    func fetch(conversationId: String) async throws -> String?
}

// MARK: discussion protocol useCase

public protocol DiscussionUseCasesProtocol {
    var getDiscussions: GetDiscussionUseCaseProtocol { get }
    var createDiscussion: CreateDiscussionUseCaseProtocol { get }
    var getMessages: GetDiscussionMessagesUseCaseProtocol { get }
    var getMessagesWithPagination: GetDiscussionMessagesWithPaginationUseCaseProtocol { get }
    var updateDiscussionSetting: UpdateDiscussionSettingUseCaseProtocol { get }
    var deleteDiscussion: DeleteDiscussionUseCaseProtocol { get }
    var deleteAllDiscussionMessages: DeleteAllDiscussionMessagesUseCaseProtocol { get }
    var draft: DiscussionDraftUseCaseProtocol { get }
}
