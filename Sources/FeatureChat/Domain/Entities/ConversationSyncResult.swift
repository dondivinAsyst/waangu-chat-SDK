//
//  ConversationSyncResult.swift
//  FeatureChat
//
//  Result entity for conversation synchronization
//

import Foundation

// MARK: - Conversation Sync Result

public struct ConversationSyncResult {
    public var createdCount: Int = 0
    public var updatedCount: Int = 0
    public var totalSynced: Int { createdCount + updatedCount }
    public var serverTime: Date?
    public var nextCursor: String?
    public var hasMore: Bool
    public var conversationIds: [String] = []  // For Phase 2 message sync
    
    public init(
        createdCount: Int = 0,
        updatedCount: Int = 0,
        serverTime: Date? = nil,
        nextCursor: String? = nil,
        hasMore: Bool = false,
        conversationIds: [String] = []
    ) {
        self.createdCount = createdCount
        self.updatedCount = updatedCount
        self.serverTime = serverTime
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.conversationIds = conversationIds
    }
}
