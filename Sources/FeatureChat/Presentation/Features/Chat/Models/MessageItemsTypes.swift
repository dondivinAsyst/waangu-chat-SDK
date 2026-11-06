//
//  MessageItemsTypes.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 14.01.2025.
//

import Foundation

public enum MessageMenuAction: String, CaseIterable, Identifiable {
    case reply, forward, forwardSelection, copy, edit, delete
    
    public var id: String {
        return rawValue
    }

    /// Translation key for this action's label.
    public var translationKey: String {
        switch self {
        case .reply:            return ChatTranslationKeys.MENU_REPLY
        case .forward:          return ChatTranslationKeys.MENU_FORWARD
        case .forwardSelection: return ChatTranslationKeys.MENU_FORWARD
        case .copy:             return ChatTranslationKeys.MENU_COPY
        case .edit:             return ChatTranslationKeys.MENU_EDIT
        case .delete:           return ChatTranslationKeys.MENU_DELETE
        }
    }
    
    var systemImage: String {
        switch self {
        case .reply:
            return "arrowshape.turn.up.left"
        case .forward, .forwardSelection:
            return "paperplane"
        case .copy:
            return "doc.on.doc"
        case .edit:
            return "pencil"
        case .delete:
            return "trash"
        }
    }

    /// Actions shown in the long-press context menu for a message row.
    static func menuActions(for message: MessageDataItem?) -> [MessageMenuAction] {
        MessageMenuAction.allCases.filter { action in
            switch action {
            case .forwardSelection:
                return false
            case .forward, .copy:
                // A view-once message is only ever seen in its viewer: nothing
                // to pass on or copy out of it.
                return message?.isViewOnce != true
            case .edit:
                guard let message else { return false }
                return message.isSentByMe
                    && message.typeMessage == .TEXT
                    && !message.isDeleted
            default:
                return true
            }
        }
    }
}

public enum Reaction: Int {
    case like
    case heart
    case laugh
    case shocked
    case sad
    case pray
    case more
    
    var emoji: String {
        switch self {
        case .like:
            return "👍"
        case .heart:
            return "❤️"
        case .laugh:
            return "😂"
        case .shocked:
            return "😲"
        case .sad:
            return "😢"
        case .pray:
            return "🙏"
        case .more:
            return "+"
        }
    }

    /// Bundled Lottie sticker in `Resources/Reactions/`.
    var lottieAssetName: String? {
        switch self {
        case .like: return "reaction_like"
        case .heart: return "reaction_heart"
        case .laugh: return "reaction_laugh"
        case .shocked: return "reaction_shocked"
        case .sad: return "reaction_sad"
        case .pray: return "reaction_pray"
        case .more: return nil
        }
    }

    /// Stagger order is reversed for sent bubbles (WhatsApp/Telegram-style).
    func entranceDelayIndex(for direction: MessageDirection, itemCount: Int = 7) -> Int {
        direction == .sent ? (itemCount - rawValue - 1) : rawValue
    }
}

public enum AdminMessageType: String {
    case channelCreation
    case memberAdded
    case memberLeft
    case channelNameChanged
}

 enum MessageType: Hashable {
    case admin(_ type: AdminMessageType), text, photo, video, audio
    
    var title: String {
        switch self {
            case .admin: return "admin"
            case .text: return "text"
            case .photo: return "photo"
            case .video: return "video"
            case .audio: return "audio"
        }
    }
    
    var isAdminMessage: Bool {
        if case .admin = self {
            return true
        } else {
            return false
        }
    }
    
    var iconName: String {
        switch self {
        case .admin:
            return "megaphone.fill"
        case .text:
            return ""
        case .photo:
            return "photo.fill"
        case .video:
            return "video.fill"
        case .audio:
            return "mic.fill"
        }
    }
    
    init?(_ stringValue: String) {
        switch stringValue {
        case .text:
            self = .text
        case "photo":
            self = .photo
        case "video":
            self = .video
        case "audio":
            self = .audio
        default:
            if let adminMessageType = AdminMessageType(rawValue: stringValue) {
                self = .admin(adminMessageType)
            } else {
                return nil
            }
        }
    }
}

extension MessageType: Equatable {
    public static func == (lhs: MessageType, rhs: MessageType) -> Bool {
        switch (lhs, rhs) {
        case (.admin(let leftAdmin), .admin(let rightAdmin)):
            return leftAdmin == rightAdmin
        case (.text, .text):
            return true
        case (.photo, .photo):
            return true
        case (.video, .video):
            return true
        case (.audio, .audio):
            return true
        default:
            return false
        }
    }
}

public enum MessageDirection {
    case sent, received
    
 public static var random: MessageDirection {
        return [MessageDirection.sent, MessageDirection.received].randomElement() ?? .sent
    }
}
