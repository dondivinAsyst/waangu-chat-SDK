//
//  ChatRoomJoinRequestCoordinator.swift
//  FeatureChat
//

import Foundation

/// Syncs pending join requests and refreshes timeline actions for group admins.
enum ChatRoomJoinRequestCoordinator {

    static func syncIfNeeded(
        isGroup: Bool,
        isGroupAdmin: Bool,
        isJoinApprovalRequired: Bool,
        conversationId: String,
        groupUseCases: GroupUseCasesProtocol?
    ) async {
        guard isGroup, isGroupAdmin, isJoinApprovalRequired, let groupUseCases else { return }

        do {
            _ = try await groupUseCases.syncJoinRequests.execute(groupId: conversationId)
        } catch {
            #if DEBUG
            print("Join request sync failed, reconciling from GRDB pending table: \(error)")
            #endif
            _ = try? await groupUseCases.reconcileJoinRequests.execute(groupId: conversationId)
        }
    }

    @discardableResult
    static func refreshIfNeeded(
        isGroup: Bool,
        isGroupAdmin: Bool,
        isJoinApprovalRequired: Bool,
        conversationId: String,
        groupUseCases: GroupUseCasesProtocol?,
        reloadChatActions: () async -> Void
    ) async -> Int {
        await syncIfNeeded(
            isGroup: isGroup,
            isGroupAdmin: isGroupAdmin,
            isJoinApprovalRequired: isJoinApprovalRequired,
            conversationId: conversationId,
            groupUseCases: groupUseCases
        )
        await reloadChatActions()
        guard let groupUseCases else { return 0 }
        return (try? await groupUseCases.fetchPendingJoinRequests.execute(groupId: conversationId))?.count ?? 0
    }
}
