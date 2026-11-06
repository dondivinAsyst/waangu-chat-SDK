//
//  GroupPermissionsRepository.swift
//  FeatureChat
//

import Foundation

final class GroupPermissionsRepository: GroupPermissionsRepositoryProtocol {

    private let localDataSource: LocalGroupPermissionsDataSourceProtocol
    private let remoteDataSource: RemoteGroupPermissionsDataSourceProtocol

    init(
        localDataSource: LocalGroupPermissionsDataSourceProtocol,
        remoteDataSource: RemoteGroupPermissionsDataSourceProtocol
    ) {
        self.localDataSource = localDataSource
        self.remoteDataSource = remoteDataSource
    }

    func getPermissions(groupLocalId: String) async throws -> GroupPermissions? {
        try await localDataSource.fetch(groupLocalId: groupLocalId)
    }

    func updatePermissions(
        _ permissions: GroupPermissions,
        groupLocalId: String,
        groupServerId: String
    ) async throws {
        let request = GroupPermissionsMapper.toRequest(
            groupServerId: groupServerId,
            permissions: permissions
        )
        // API first — if this throws the local store is not touched
        try await remoteDataSource.updatePermissions(request)
        // On success, persist locally
        try await localDataSource.save(permissions, groupLocalId: groupLocalId, groupServerId: groupServerId)
    }

    func savePermissionsLocally(
        _ permissions: GroupPermissions,
        groupLocalId: String,
        groupServerId: String?
    ) async throws {
        try await localDataSource.save(permissions, groupLocalId: groupLocalId, groupServerId: groupServerId)
    }
}
