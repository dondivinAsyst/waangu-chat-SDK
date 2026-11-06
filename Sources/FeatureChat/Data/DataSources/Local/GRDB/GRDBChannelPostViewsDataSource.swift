//
//  GRDBChannelPostViewsDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Read receipts, counted per post.
///
/// `ReadReceiptModel` is already written by the sync for every participant that
/// opens a message; on a broadcast that set *is* the audience, so counting the
/// rows with a `readAt` is the whole implementation.
final class GRDBChannelPostViewsDataSource: ChannelPostViewCounting {

    private let store: any DatabaseRepositoryProtocol

    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }

    func viewCounts(conversationId: String) async -> [String: Int] {
        guard !conversationId.isEmpty else { return [:] }

        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId))
        )
        guard let receipts = try? await store.fetch(ReadReceiptModel.self, query: query) else {
            return [:]
        }

        var counts: [String: Int] = [:]
        for receipt in receipts where receipt.readAt != nil {
            counts[receipt.messageId, default: 0] += 1
        }
        return counts
    }
}
