//
//  ChatRoomReadReceiptCoordinator.swift
//  FeatureChat
//

import Foundation

/// Publishes read receipts for visible incoming messages via `waangu-chat/mark-as-read`.
///
/// System records are never acknowledged: the id on one is a call or group-event
/// id, which the server cannot resolve to a message, so a receipt for it is
/// published against nothing. Locally written call logs already start at `.SEEN`,
/// but the copies the backend projects into a conversation — call records and
/// group events alike — arrive `DELIVERED` and would otherwise qualify.
enum ChatRoomReadReceiptCoordinator {

    static func unreadIncomingMessages(
        in messages: [MessageDataItem],
        currentUserId: String = CurrentSessionInfo.shared.currentUid
    ) -> [MessageDataItem] {
        messages.filter {
            $0.senderId != currentUserId
                && $0.status != .SEEN
                && !$0.codeMessage.isEmpty
                && !$0.typeMessage.isSystemRecord
        }
    }
}
