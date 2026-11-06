//
//  GroupJoinApprovalResolver.swift
//  FeatureChat
//

import Foundation

/// Resolves whether join requests require admin approval.
/// Reads `GroupPermissions.approveNewMembers` first, then falls back to legacy `GroupSettings.approvalRequired`.
enum GroupJoinApprovalResolver {
    static func isApprovalRequired(
        groupLocalId: String,
        legacySettings: GroupSettings?,
        permissionsUseCases: GroupPermissionsUseCasesProtocol?
    ) async -> Bool {
        if let permissionsUseCases,
           let permissions = try? await permissionsUseCases.getPermissions.execute(groupLocalId: groupLocalId) {
            return permissions.approveNewMembers
        }
        return legacySettings?.approvalRequired ?? false
    }
}
