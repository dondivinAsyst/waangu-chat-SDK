//
//  HTTPConversationSyncDataSource.swift
//  FeatureChat
//
//  HTTP implementation of conversation synchronization data source
//

import Foundation
import WaanguCoreKit

public final class HTTPConversationSyncDataSource: RemoteConversationSyncDataSourceProtocol {
    
    // MARK: - Properties
    
    private let apiClient: any APIClientProtocol
    
    // MARK: - Initialization
    
    public init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    // MARK: - RemoteConversationSyncDataSourceProtocol
    
    public func syncConversations(since: Date?, limit: Int) async throws -> ConversationSyncResponseDTO {
        return try await apiClient.request(
            endpoint: ConversationSyncEndpoints.syncConversations(since: since, limit: limit)
        )
    }
    
    public func syncConversationMessages(conversationId: String, since: Date?, limit: Int) async throws -> MessageSyncResponseDTO {
        return try await apiClient.request(
            endpoint: ConversationSyncEndpoints.syncConversationMessages(
                conversationId: conversationId,
                since: since,
                limit: limit
            )
        )
    }
}
