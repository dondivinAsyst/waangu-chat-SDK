//
//  ChatsTabRoute.swift
//  FeatureChat
//
//  Chat tab navigation routes
//

import SwiftUI
import WaanguNavigationKit
import WaanguCoreKit

public enum ChatsTabRoute: StackRoute {
    case root
    /// Ouvre une conversation, éventuellement sur un parcours financier.
    case chatRoom(type: ConversationType, isArchived: Bool)
    /// La conversation Waangu Copilot — sur l'appareil, ouverte comme une conversation.
    case copilot(conversationId: String)
    case archiveChat
    case profileView(
        contactId: String,
        discussionId: String,
        fallbackPhone: String?,
        fallbackDisplayName: String?,
        isBlocked:Bool
    )
    case groupInfoView(
        discussionId: String,
        groupName: String
    )
    case groupPermissions(
        discussionId: String,
        groupName: String
    )
    case pendingJoinRequests(
        discussionId: String,
        groupName: String
    )
}
