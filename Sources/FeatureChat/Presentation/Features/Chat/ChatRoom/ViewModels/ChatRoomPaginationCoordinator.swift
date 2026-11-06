//
//  ChatRoomPaginationCoordinator.swift
//  FeatureChat
//

import Foundation
import UIKit

/// Loads paginated message pages for a conversation.
enum ChatRoomPaginationCoordinator {

    struct PageResult {
        let messages: [MessageDataItem]
        let allMediaMessages: [MessageDataItem]
        let oldestLoadedDate: Date?
        let hasMore: Bool
    }

    static func pageSize() -> Int {
        let screenHeight = UIScreen.main.bounds.height
        let averageCellHeight: CGFloat = 72
        let buffer = 2
        return Int(screenHeight / averageCellHeight) + buffer
    }

    static func loadInitial(
        conversationId: String,
        pageSize: Int,
        discussionsUseCases: DiscussionUseCasesProtocol
    ) async throws -> PageResult {
        let page = try await discussionsUseCases.getMessagesWithPagination.execute(
            conversationId: conversationId,
            before: nil,
            pageSize: pageSize
        )
        return normalize(page ?? [], pageSize: pageSize)
    }

    static func loadMore(
        conversationId: String,
        before: Date,
        pageSize: Int,
        discussionsUseCases: DiscussionUseCasesProtocol
    ) async throws -> PageResult? {
        let page = try await discussionsUseCases.getMessagesWithPagination.execute(
            conversationId: conversationId,
            before: before,
            pageSize: pageSize
        )
        guard let page, !page.isEmpty else { return nil }
        return normalize(page, pageSize: pageSize)
    }

    private static func normalize(_ rawMessages: [MessageDataItem], pageSize: Int) -> PageResult {
        let sorted = rawMessages.sorted { $0.createdAt < $1.createdAt }
        let media = sorted.filter { ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce }
        return PageResult(
            messages: sorted,
            allMediaMessages: media,
            oldestLoadedDate: sorted.first?.createdAt,
            hasMore: rawMessages.count >= pageSize
        )
    }
}
