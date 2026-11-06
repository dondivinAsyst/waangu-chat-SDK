//
//  LocalChatActionsDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

protocol LocalChatActionsDataSourceProtocol {
    func saveChatAction(_ action: ChatActionItem) async throws
    func fetchChatActions(conversationId: String) async throws -> [ChatActionItem]
    func fetchChatActionsWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [ChatActionItem]
    func deleteChatAction(actionId: String) async throws
    func deleteAllChatActions(conversationId: String) async throws
    func chatActionExists(actionId: String) async throws -> Bool
}
