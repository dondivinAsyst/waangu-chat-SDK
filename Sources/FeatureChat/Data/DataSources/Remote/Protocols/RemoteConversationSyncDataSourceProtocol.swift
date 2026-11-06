//
//  RemoteConversationSyncDataSourceProtocol.swift
//  FeatureChat
//
//  Protocol for remote conversation synchronization data source
//

import Foundation

public protocol RemoteConversationSyncDataSourceProtocol {
    /// Syncs conversations changed since the given date
    /// - Parameters:
    ///   - since: Optional date to fetch changes from (nil = all conversations)
    ///   - limit: Maximum number of conversations to fetch
    /// - Returns: Conversation sync response with changed conversations
    func syncConversations(since: Date?, limit: Int) async throws -> ConversationSyncResponseDTO
    
    /// Syncs messages for a specific conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID to sync messages for
    ///   - since: Optional date to fetch messages from (nil = all messages)
    ///   - limit: Maximum number of messages to fetch
    /// - Returns: Message sync response with messages
    func syncConversationMessages(conversationId: String, since: Date?, limit: Int) async throws -> MessageSyncResponseDTO
}
