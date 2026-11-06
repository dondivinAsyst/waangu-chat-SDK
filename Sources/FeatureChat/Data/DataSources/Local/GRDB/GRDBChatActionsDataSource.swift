//
//  GRDBChatActionsDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class GRDBChatActionsDataSource: LocalChatActionsDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol
    private let mapper: ChatActionMapperProtocol

    init(
        store: any DatabaseRepositoryProtocol,
        mapper: ChatActionMapperProtocol
    ) {
        self.store = store
        self.mapper = mapper
    }

    func saveChatAction(_ action: ChatActionItem) async throws {
        let model = mapper.toGRDB(action)
        try await store.save(model)
    }

    func fetchChatActions(conversationId: String) async throws -> [ChatActionItem] {
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: false)]
        )
        let models = try await store.fetch(ChatActionModel.self, query: query)
        return models.map { mapper.toDomain($0) }
    }

    func fetchChatActionsWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [ChatActionItem] {
        let query: QuerySpec
        if let cursor {
            query = QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND timestamp < %@",
                    .string(conversationId),
                    .date(cursor)
                ),
                sort: [SortSpec("timestamp", ascending: false)],
                limit: pageSize
            )
        } else {
            query = QuerySpec(
                filter: FilterSpec("conversation_id == %@", .string(conversationId)),
                sort: [SortSpec("timestamp", ascending: false)],
                limit: pageSize
            )
        }
        let models = try await store.fetch(ChatActionModel.self, query: query)
        return models.map { mapper.toDomain($0) }
    }

    func deleteChatAction(actionId: String) async throws {
        try await store.delete(ChatActionModel.self, id: actionId)
    }

    func deleteAllChatActions(conversationId: String) async throws {
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId))
        )
        try await store.deleteAll(ChatActionModel.self, query: query)
    }

    func chatActionExists(actionId: String) async throws -> Bool {
        let action = try await store.fetchOne(ChatActionModel.self, id: actionId)
        return action != nil
    }
}
