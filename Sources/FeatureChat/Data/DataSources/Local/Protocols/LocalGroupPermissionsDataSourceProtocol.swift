//
//  LocalGroupPermissionsDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

protocol LocalGroupPermissionsDataSourceProtocol {
    func fetch(groupLocalId: String) async throws -> GroupPermissions?
    func save(_ permissions: GroupPermissions, groupLocalId: String, groupServerId: String?) async throws
    func delete(groupLocalId: String) async throws
}
