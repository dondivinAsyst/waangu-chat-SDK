import Foundation

protocol LocalDiscussionDataSourceProtocol {
    func fetchDiscussions() async throws -> [DiscussionChatItem]
    func saveDiscussion(_ discussion: DiscussionChatItem) async throws
    func updateDiscussionSetting(_ discussion: DiscussionChatItem) async throws
    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem]
    func fetchMessagesWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [MessageDataItem]
    func deleteDiscussion(conversationId: String) async throws
    func deleteAllDiscussionMessages(conversationId: String) async throws
    func deleteAllDiscussions() async throws
    func clearUnreadCount(conversationId: String) async throws
    /// Stores the composer text the user left behind, or clears it when the text
    /// is empty. Whitespace-only counts as empty.
    func saveDraft(conversationId: String, text: String) async throws
    /// The draft stored for a conversation, so the room can restore it.
    func fetchDraft(conversationId: String) async throws -> String?
    func outboundConversationId(for localConversationId: String) async -> String
    /// The group id to put on an outbound message, or nil when not a group.
    func outboundGroupId(for localConversationId: String) async -> String?
}
