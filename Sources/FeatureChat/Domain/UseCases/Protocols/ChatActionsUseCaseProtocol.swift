//
//  ChatActionsUseCaseProtocol.swift
//  FeatureChat
//
//  Use case protocol for managing chat actions
//

import Foundation

public protocol ChatActionsUseCaseProtocol {
    /// Record a chat action
    func recordAction(_ action: ChatActionItem) async throws
    
    /// Fetch all actions for a conversation
    func fetchActions(conversationId: String) async throws -> [ChatActionItem]
    
    /// Fetch actions with pagination
    func fetchActionsWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [ChatActionItem]
    
    /// Delete a specific action
    func deleteAction(actionId: String) async throws
    
    /// Delete all actions for a conversation
    func deleteAllActions(conversationId: String) async throws
}
