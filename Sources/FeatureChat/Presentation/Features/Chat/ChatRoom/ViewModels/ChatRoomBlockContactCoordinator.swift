//
//  ChatRoomBlockContactCoordinator.swift
//  FeatureChat
//

import Foundation

/// Toggles block state for the current 1:1 chat partner.
enum ChatRoomBlockContactCoordinator {

    struct Handlers {
        let toggleBlock: (String, Bool) async throws -> Bool
        let recordChatAction: (ChatActionType, [String: String]?) async -> Void
        let showSuccess: (String) -> Void
        let showError: (String) -> Void
        let onBlockedStateChanged: (Bool) -> Void
    }

    static func toggle(
        contact: UserRoom,
        isCurrentlyBlocked: Bool,
        handlers: Handlers
    ) async {
        let newBlockedState = !isCurrentlyBlocked

        do {
            let resultBlocked = try await handlers.toggleBlock(contact.idContact, newBlockedState)

            handlers.onBlockedStateChanged(resultBlocked)

            let actionType: ChatActionType = resultBlocked ? .contactBlocked : .contactUnblocked
            let metadata = ["contactName": contact.name ?? "Unknown"]
            await handlers.recordChatAction(actionType, metadata)

            NotificationCenter.default.post(
                name: .contactBlockStatusChanged,
                object: nil,
                userInfo: [
                    "contactId": contact.idContact,
                    "isBlocked": resultBlocked
                ]
            )

            let message = resultBlocked ? "Contact blocked successfully" : "Contact unblocked successfully"
            handlers.showSuccess(message)

            NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
        } catch {
            handlers.showError(String(format: ChatErrorStrings.blockStatusFailedDetailed, error.localizedDescription))
        }
    }
}
