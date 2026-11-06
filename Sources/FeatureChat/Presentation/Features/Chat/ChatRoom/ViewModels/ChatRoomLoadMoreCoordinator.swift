//
//  ChatRoomLoadMoreCoordinator.swift
//  FeatureChat
//

import Foundation

/// Loads older message pages when the user scrolls to the top.
enum ChatRoomLoadMoreCoordinator {

    struct AppliedPage {
        let insertedMessages: [MessageDataItem]
        let oldestLoadedDate: Date?
        let hasMore: Bool
    }

    static func loadNextPage(
        conversationId: String,
        before: Date,
        discussionsUseCases: DiscussionUseCasesProtocol
    ) async throws -> AppliedPage? {
        guard let result = try await ChatRoomPaginationCoordinator.loadMore(
            conversationId: conversationId,
            before: before,
            pageSize: ChatRoomPaginationCoordinator.pageSize(),
            discussionsUseCases: discussionsUseCases
        ) else { return nil }

        return AppliedPage(
            insertedMessages: result.messages,
            oldestLoadedDate: result.oldestLoadedDate,
            hasMore: result.hasMore
        )
    }
}
