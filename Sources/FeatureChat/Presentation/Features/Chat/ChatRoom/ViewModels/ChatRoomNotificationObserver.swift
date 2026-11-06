//
//  ChatRoomNotificationObserver.swift
//  FeatureChat
//

import Combine
import Foundation

/// Wires NotificationCenter publishers for a single chat room session.
enum ChatRoomNotificationObserver {

    struct Handlers {
        var onCallHistoryPersisted: (MessageDataItem) -> Void
        var onContactBlockStatusChanged: (String, Bool) -> Void
        var onGroupJoinRequestReceived: ([AnyHashable: Any]) -> Void
        var onChatActionsDidChange: () -> Void
        var onGroupUpdated: () -> Void
    }

    static func wire(
        conversationId: String,
        currentReceiverContactId: @escaping () -> String?,
        handlers: Handlers,
        subscriptions: inout Set<AnyCancellable>
    ) {
        NotificationCenter.default.publisher(for: .callHistoryPersisted)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let userInfo = notification.userInfo,
                      let msg = userInfo["message"] as? MessageDataItem,
                      let convId = userInfo["conversationId"] as? String,
                      convId == conversationId else { return }
                handlers.onCallHistoryPersisted(msg)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .contactBlockStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let userInfo = notification.userInfo,
                      let contactId = userInfo["contactId"] as? String,
                      let isBlocked = userInfo["isBlocked"] as? Bool,
                      contactId == currentReceiverContactId() else { return }
                handlers.onContactBlockStatusChanged(contactId, isBlocked)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .groupJoinRequestReceived)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let userInfo = notification.userInfo else { return }
                handlers.onGroupJoinRequestReceived(userInfo)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .chatActionsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let changedId = notification.userInfo?["conversationId"] as? String,
                      changedId == conversationId else { return }
                handlers.onChatActionsDidChange()
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .groupActivated)
            .merge(with: NotificationCenter.default.publisher(for: .groupSyncStatusChanged))
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let localId = notification.userInfo?["localId"] as? String,
                      localId == conversationId else { return }
                handlers.onGroupUpdated()
            }
            .store(in: &subscriptions)
    }
}
