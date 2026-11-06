//
//  GroupPermissionsUseCasesProtocol.swift
//  FeatureChat
//

import Foundation

public protocol GetGroupPermissionsUseCaseProtocol {
    func execute(groupLocalId: String) async throws -> GroupPermissions?
}

public protocol UpdateGroupPermissionsUseCaseProtocol {
    /// Calls the API, then on success saves locally. Throws if API fails.
    func execute(
        permissions: GroupPermissions,
        groupLocalId: String,
        groupServerId: String
    ) async throws
}

public protocol GroupPermissionsUseCasesProtocol {
    var getPermissions: GetGroupPermissionsUseCaseProtocol { get }
    var updatePermissions: UpdateGroupPermissionsUseCaseProtocol { get }
}
