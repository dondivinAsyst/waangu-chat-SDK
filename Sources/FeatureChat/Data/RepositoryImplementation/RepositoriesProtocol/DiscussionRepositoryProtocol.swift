import Foundation

public protocol DiscussionRepositoryProtocol {
    func fetchDiscussions() async throws -> [DiscussionChatItem]
    func getDiscussionById(conversationId: String) async throws -> DiscussionChatItem?
    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem]
    func fetchMessagesWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [MessageDataItem]
    func saveDiscussion(_ discussion: DiscussionChatItem) async throws
    func updateDiscussionSetting(_ discussion: DiscussionChatItem) async throws
    func deleteDiscussion(conversationId: String) async throws
    func deleteAllDiscussionMessages(conversationId: String) async throws
    func clearUnreadCount(conversationId: String) async throws
    /// Stores the composer text the user left behind; empty text clears it.
    func saveDraft(conversationId: String, text: String) async throws
    /// The draft stored for a conversation, so the room can restore it.
    func fetchDraft(conversationId: String) async throws -> String?
    /// Backend conversation id for MQTT publish (`serverId` when linked, else local id).
    func outboundConversationId(for localConversationId: String) async -> String
    /// The group id to put on an outbound message, or nil when not a group.
    func outboundGroupId(for localConversationId: String) async -> String?
    
    // MARK: - Sync
    /// Synchronizes conversations with the server
    /// - Parameters:
    ///   - since: Optional date to fetch changes from (nil = all conversations)
    ///   - limit: Maximum number of conversations to fetch
    /// - Returns: Result containing sync statistics
    func syncConversations(since: Date?, limit: Int) async throws -> ConversationSyncResult
    
    /// Synchronizes messages for a specific conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID to sync messages for
    ///   - since: Optional date to fetch messages from (nil = all messages)
    ///   - limit: Maximum number of messages to fetch
    /// - Returns: Number of messages synced
    func syncConversationMessages(conversationId: String, since: Date?, limit: Int) async throws -> Int
    
    /// Master sync orchestrator: Alternates between fetching conversations and syncing messages
    /// Loops: Fetch conversations → Sync messages for each → Repeat if hasMore
    /// - Parameter limit: Maximum items per batch
    func performFullSync(limit: Int) async throws

    /// Folds together inbox rows that are the same thread stored twice.
    ///
    /// Runs after a sync, when both writers have had their say, and only until
    /// it succeeds once per repair version — see
    /// `ConversationDeduplicationService`. Never throws: a failed repair is not
    /// a reason to fail login.
    func deduplicateConversationsIfNeeded() async
}
