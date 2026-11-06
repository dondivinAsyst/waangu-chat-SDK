//
//  GRDBGroupJoinRequestDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class GRDBGroupJoinRequestDataSource: LocalGroupJoinRequestDataSourceProtocol {
    private let store: any DatabaseRepositoryProtocol
    private let mapper: GroupJoinRequestMapperProtocol

    init(
        store: any DatabaseRepositoryProtocol,
        mapper: GroupJoinRequestMapperProtocol = GroupJoinRequestMapper()
    ) {
        self.store = store
        self.mapper = mapper
    }

    func fetchPending(groupLocalId: String) async throws -> [GroupJoinRequest] {
        let query = QuerySpec(
            filter: FilterSpec("group_local_id == %@", .string(groupLocalId)),
            sort: [SortSpec("requested_at", ascending: false)]
        )
        let models = try await store.fetch(GroupJoinRequestModel.self, query: query)
        return models.map { mapper.toDomain($0) }
    }

    func saveAll(_ requests: [GroupJoinRequest], groupLocalId: String) async throws {
        let deleteQuery = QuerySpec(
            filter: FilterSpec("group_local_id == %@", .string(groupLocalId))
        )
        try await store.deleteAll(GroupJoinRequestModel.self, query: deleteQuery)

        for request in requests {
            let model = mapper.toGRDB(request, groupLocalId: groupLocalId)
            try await store.save(model)
        }
    }

    func remove(requestId: String, groupLocalId: String) async throws {
        if let existing = try await store.fetchOne(GroupJoinRequestModel.self, id: requestId),
           existing.groupLocalId == groupLocalId {
            try await store.delete(GroupJoinRequestModel.self, id: requestId)
        }
    }

    func upsert(_ request: GroupJoinRequest, groupLocalId: String) async throws {
        let model = mapper.toGRDB(request, groupLocalId: groupLocalId)
        try await store.save(model)
    }
}
