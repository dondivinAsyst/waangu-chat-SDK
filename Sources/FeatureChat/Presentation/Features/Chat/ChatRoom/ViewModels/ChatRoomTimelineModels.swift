//
//  ChatRoomTimelineModels.swift
//  FeatureChat
//

import Foundation

enum MessageRow: Identifiable, Equatable {
    case message(MessageDataItem)
    case mediaGroup(idGroup: String, messages: [MessageDataItem])
    case checkpoint(ChatActionItem)
    case encryptionBanner
    case groupIntro(GroupChatIntroContent)

    var id: String {
        switch self {
        case .message(let msg):
            return msg.id
        case .mediaGroup(let id, _):
            return id
        case .checkpoint(let action):
            return action.id
        case .encryptionBanner:
            return "encryption-banner"
        case .groupIntro:
            return GroupChatIntroContent.rowId
        }
    }
}

struct MessageSection: Equatable, Identifiable {
    let id: String
    let date: String
    var rows: [MessageRow]
}

struct ChatRoomTimelineInput: Equatable {
    let messages: [MessageDataItem]
    let chatActions: [ChatActionItem]
    let shouldShowGroupIntroHeader: Bool
    let isGroupAdmin: Bool
    let groupIntroContent: GroupChatIntroContent?
}
