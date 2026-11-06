//
//  ChatRoomGroupMembershipCoordinator.swift
//  FeatureChat
//

import Foundation

/// Reloads group metadata and membership / read-only state.
enum ChatRoomGroupMembershipCoordinator {

    struct RefreshResult {
        let groupChat: GroupChat?
        let isGroupReadOnly: Bool
        let isJoinApprovalRequired: Bool
        let shouldRebuildTimeline: Bool
    }

    static func fetchGroup(
        isGroup: Bool,
        conversationId: String,
        groupUseCases: GroupUseCasesProtocol?
    ) async -> GroupChat? {
        guard isGroup, let groupUseCases else { return nil }
        return try? await groupUseCases.getGroup.execute(groupId: conversationId)
    }

    static func refresh(
        isGroup: Bool,
        conversationId: String,
        shouldShowGroupIntroHeader: Bool,
        groupUseCases: GroupUseCasesProtocol?,
        permissionsUseCases: GroupPermissionsUseCasesProtocol?
    ) async -> RefreshResult {
        guard isGroup, let groupUseCases else {
            return RefreshResult(
                groupChat: nil,
                isGroupReadOnly: false,
                isJoinApprovalRequired: false,
                shouldRebuildTimeline: false
            )
        }

        guard let group = try? await groupUseCases.getGroup.execute(groupId: conversationId) else {
            return RefreshResult(
                groupChat: nil,
                isGroupReadOnly: true,
                isJoinApprovalRequired: false,
                shouldRebuildTimeline: false
            )
        }

        let currentUid = CurrentSessionInfo.shared.currentUid
        let member = group.members.first { $0.userId == currentUid }
        let isReadOnly = !(member?.isActive ?? false)
        let joinApprovalRequired = await GroupJoinApprovalResolver.isApprovalRequired(
            groupLocalId: conversationId,
            legacySettings: group.settings,
            permissionsUseCases: permissionsUseCases
        )

        return RefreshResult(
            groupChat: group,
            isGroupReadOnly: isReadOnly,
            isJoinApprovalRequired: joinApprovalRequired,
            shouldRebuildTimeline: shouldShowGroupIntroHeader
        )
    }
}
