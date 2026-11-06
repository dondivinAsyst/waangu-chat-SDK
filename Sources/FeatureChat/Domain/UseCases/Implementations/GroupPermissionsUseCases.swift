//
//  GroupPermissionsUseCases.swift
//  FeatureChat
//

import Foundation

// MARK: - Get

final class GetGroupPermissionsUseCase: GetGroupPermissionsUseCaseProtocol {
    private let repository: GroupPermissionsRepositoryProtocol

    init(repository: GroupPermissionsRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupLocalId: String) async throws -> GroupPermissions? {
        try await repository.getPermissions(groupLocalId: groupLocalId)
    }
}

// MARK: - Update

final class UpdateGroupPermissionsUseCase: UpdateGroupPermissionsUseCaseProtocol {
    private let repository: GroupPermissionsRepositoryProtocol

    init(repository: GroupPermissionsRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        permissions: GroupPermissions,
        groupLocalId: String,
        groupServerId: String
    ) async throws {
        try await repository.updatePermissions(
            permissions,
            groupLocalId: groupLocalId,
            groupServerId: groupServerId
        )
    }
}

// MARK: - Container

final class GroupPermissionsUseCases: GroupPermissionsUseCasesProtocol {
    let getPermissions: GetGroupPermissionsUseCaseProtocol
    let updatePermissions: UpdateGroupPermissionsUseCaseProtocol

    init(repository: GroupPermissionsRepositoryProtocol) {
        self.getPermissions = GetGroupPermissionsUseCase(repository: repository)
        self.updatePermissions = UpdateGroupPermissionsUseCase(repository: repository)
    }
}
