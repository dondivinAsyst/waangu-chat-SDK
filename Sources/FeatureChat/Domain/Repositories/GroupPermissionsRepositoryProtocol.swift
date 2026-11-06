//
//  GroupPermissionsRepositoryProtocol.swift
//  FeatureChat
//

import Foundation

protocol GroupPermissionsRepositoryProtocol {
    func getPermissions(groupLocalId: String) async throws -> GroupPermissions?
    /// Calls API first; on success updates GRDB. Throws on API failure.
    func updatePermissions(_ permissions: GroupPermissions, groupLocalId: String, groupServerId: String) async throws
    /// Saves permissions locally only (e.g. for pre-synced groups or seeding from group fetch).
    func savePermissionsLocally(_ permissions: GroupPermissions, groupLocalId: String, groupServerId: String?) async throws
}
