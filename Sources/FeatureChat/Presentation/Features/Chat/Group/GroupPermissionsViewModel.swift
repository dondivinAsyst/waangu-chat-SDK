//
//  GroupPermissionsViewModel.swift
//  FeatureChat
//

import Foundation

@MainActor
final class GroupPermissionsViewModel: ObservableObject {

    @Published var permissions: GroupPermissions
    @Published var isUpdating = false
    @Published var errorMessage: String?

    let isAdmin: Bool
    private let groupLocalId: String
    private let groupServerId: String?
    private let permissionsUseCases: GroupPermissionsUseCasesProtocol

    init(
        group: GroupChat,
        permissionsUseCases: GroupPermissionsUseCasesProtocol
    ) {
        self.groupLocalId = group.localId
        self.groupServerId = group.serverId
        self.permissionsUseCases = permissionsUseCases
        self.isAdmin = group.isCurrentUserAdmin(
            currentUserId: CurrentSessionInfo.shared.currentUid
        )

        self.permissions = GroupPermissionsViewModel.migrate(from: group.settings)
        Task {
            if let stored = try? await permissionsUseCases.getPermissions.execute(groupLocalId: group.localId) {
                permissions = stored
            }
        }
    }

    // MARK: - Toggle a single flag

    func toggle(_ keyPath: WritableKeyPath<GroupPermissions, Bool>, value: Bool) {
        guard groupServerId != nil else {
            errorMessage = "Group is not yet synced with the server."
            return
        }

        var updated = permissions
        updated[keyPath: keyPath] = value

        Task {
            isUpdating = true
            defer { isUpdating = false }

            do {
                try await permissionsUseCases.updatePermissions.execute(
                    permissions: updated,
                    groupLocalId: groupLocalId,
                    groupServerId: groupServerId!
                )
                // Update published state only after API success
                permissions = updated
            } catch {
                errorMessage = String(format: ChatErrorStrings.permissionUpdateFailed, error.localizedDescription)
                // Don't update permissions — the toggle will revert because we never set it
            }
        }
    }

    // MARK: - Seed from GroupSettings (migration helper)

    private static func migrate(from settings: GroupSettings) -> GroupPermissions {
        GroupPermissions(
            sendMessages: !settings.onlyAdminsCanSend,
            addMembers: !settings.onlyAdminsCanAddMembers,
            inviteLink: settings.isInviteLinkActive,
            changeGroupInfo: !settings.onlyAdminsCanEditInfo,
            approveNewMembers: settings.approvalRequired,
            onlyAdminsCanPost: settings.onlyAdminsCanSend,
            sendMessagesHistory: settings.sendMessagesHistory
        )
    }
}
