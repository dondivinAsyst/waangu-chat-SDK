//
//  ChatActionsUseCase.swift
//  FeatureChat
//

import Foundation

final class ChatActionsUseCase: ChatActionsUseCaseProtocol {

    private let localDataSource: LocalChatActionsDataSourceProtocol

    init(localDataSource: LocalChatActionsDataSourceProtocol) {
        self.localDataSource = localDataSource
    }

    func recordAction(_ action: ChatActionItem) async throws {
        try await localDataSource.saveChatAction(action)
    }

    func fetchActions(conversationId: String) async throws -> [ChatActionItem] {
        try await localDataSource.fetchChatActions(conversationId: conversationId)
    }

    func fetchActionsWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [ChatActionItem] {
        try await localDataSource.fetchChatActionsWithPagination(
            conversationId: conversationId,
            before: cursor,
            pageSize: pageSize
        )
    }

    func deleteAction(actionId: String) async throws {
        try await localDataSource.deleteChatAction(actionId: actionId)
    }

    func deleteAllActions(conversationId: String) async throws {
        try await localDataSource.deleteAllChatActions(conversationId: conversationId)
    }
}
