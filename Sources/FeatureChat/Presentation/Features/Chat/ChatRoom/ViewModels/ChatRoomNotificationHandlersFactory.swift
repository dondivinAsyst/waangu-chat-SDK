//
//  ChatRoomNotificationHandlersFactory.swift
//  FeatureChat
//

import Foundation

/// Builds notification handler closures for a chat room session.
enum ChatRoomNotificationHandlersFactory {

    struct Dependencies {
        let conversationId: String
        let isGroup: () -> Bool
        let isGroupAdmin: () -> Bool
        let isJoinApprovalRequired: () -> Bool
        let groupUseCases: () -> GroupUseCasesProtocol?
        let onCallHistoryPersisted: (MessageDataItem) -> Void
        let onContactBlockStatusChanged: (Bool) -> Void
        let onReloadChatActions: () async -> Void
        let onGroupUpdated: () -> Void
    }

    static func make(_ dependencies: Dependencies) -> ChatRoomNotificationObserver.Handlers {
        ChatRoomNotificationObserver.Handlers(
            onCallHistoryPersisted: dependencies.onCallHistoryPersisted,
            onContactBlockStatusChanged: { _, isBlocked in
                dependencies.onContactBlockStatusChanged(isBlocked)
            },
            onGroupJoinRequestReceived: { userInfo in
                guard dependencies.isGroup(),
                      dependencies.isGroupAdmin(),
                      dependencies.isJoinApprovalRequired(),
                      let request = GroupJoinRequest(notificationUserInfo: userInfo),
                      request.groupId == dependencies.conversationId,
                      let groupUseCases = dependencies.groupUseCases() else { return }

                Task {
                    do {
                        try await groupUseCases.ingestJoinRequest.execute(
                            request,
                            groupId: dependencies.conversationId
                        )
                        await dependencies.onReloadChatActions()
                    } catch {
                        #if DEBUG
                        print("Failed to ingest join request: \(error)")
                        #endif
                    }
                }
            },
            onChatActionsDidChange: {
                Task { await dependencies.onReloadChatActions() }
            },
            onGroupUpdated: dependencies.onGroupUpdated
        )
    }
}
