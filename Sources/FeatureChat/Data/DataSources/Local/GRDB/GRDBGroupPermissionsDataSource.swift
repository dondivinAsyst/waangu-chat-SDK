//
//  GRDBGroupPermissionsDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class GRDBGroupPermissionsDataSource: LocalGroupPermissionsDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol

    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }

    func fetch(groupLocalId: String) async throws -> GroupPermissions? {
        let query = QuerySpec(
            filter: FilterSpec("group_local_id == %@", .string(groupLocalId)),
            limit: 1
        )
        let models = try await store.fetch(GroupPermissionsModel.self, query: query)
        guard let model = models.first else { return nil }
        return GroupPermissionsMapper.toDomain(model)
    }

    func save(_ permissions: GroupPermissions, groupLocalId: String, groupServerId: String?) async throws {
        let model = GroupPermissionsMapper.toModel(permissions, groupLocalId: groupLocalId, groupServerId: groupServerId)
        try await store.save(model)
    }

    func delete(groupLocalId: String) async throws {
        try await store.delete(GroupPermissionsModel.self, id: groupLocalId)
    }
}
