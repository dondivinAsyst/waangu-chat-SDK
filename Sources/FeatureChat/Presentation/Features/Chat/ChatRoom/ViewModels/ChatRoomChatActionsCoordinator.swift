//
//  ChatRoomChatActionsCoordinator.swift
//  FeatureChat
//

import Foundation

/// Fetches and records timeline chat actions (join requests, blocks, etc.).
enum ChatRoomChatActionsCoordinator {

    static func fetchActions(
        conversationId: String,
        using useCase: ChatActionsUseCaseProtocol
    ) async throws -> [ChatActionItem] {
        try await useCase.fetchActions(conversationId: conversationId)
    }

    static func makeAction(
        conversationId: String,
        actionType: ChatActionType,
        targetId: String? = nil,
        metadata: [String: String]? = nil
    ) -> ChatActionItem {
        ChatActionItem(
            conversationId: conversationId,
            actionType: actionType,
            performedBy: CurrentSessionInfo.shared.currentUid,
            targetId: targetId,
            metadata: metadata
        )
    }

    static func record(
        conversationId: String,
        actionType: ChatActionType,
        targetId: String? = nil,
        metadata: [String: String]? = nil,
        using useCase: ChatActionsUseCaseProtocol
    ) async throws -> ChatActionItem {
        let action = makeAction(
            conversationId: conversationId,
            actionType: actionType,
            targetId: targetId,
            metadata: metadata
        )
        try await useCase.recordAction(action)
        return action
    }
}
