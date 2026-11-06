//
//  ChatRoomMessageActionCoordinator.swift
//  FeatureChat
//

import Foundation
import UIKit

/// Handles copy / reply / forward / delete menu actions on message rows.
enum ChatRoomMessageActionCoordinator {

    struct SelectionUpdate {
        var selectedMessages: [MessageDataItem]?
        var messageAction: MessageMenuAction?
    }

    static func handle(
        _ action: MessageMenuAction,
        on row: MessageRow,
        selectedMessages: [MessageDataItem]?
    ) -> (copyText: String?, replyMessage: MessageRow?, selection: SelectionUpdate?) {
        let message: MessageDataItem?
        let mediaGroupMessages: [MessageDataItem]?

        switch row {
        case .mediaGroup(_, let messages):
            message = nil
            mediaGroupMessages = messages
        case .message(let msg):
            message = msg
            mediaGroupMessages = nil
        case .checkpoint, .encryptionBanner, .groupIntro:
            message = nil
            mediaGroupMessages = nil
        }

        switch action {
        case .copy:
            guard let message, !message.isDeleted else { return (nil, nil, nil) }
            return (message.message.text, nil, nil)

        case .edit:
            return (nil, nil, nil)

        case .reply:
            // Deleted placeholders cannot be replied to.
            if let message, message.isDeleted { return (nil, nil, nil) }
            if let mediaGroupMessages, mediaGroupMessages.allSatisfy(\.isDeleted) {
                return (nil, nil, nil)
            }
            return (nil, row, nil)

        case .forward:
            // First tap on Forward - enter selection mode instead of immediately forwarding
            var selected = selectedMessages ?? []
            if let mediaMessages = mediaGroupMessages {
                selected.append(contentsOf: mediaMessages.filter { !$0.isDeleted })
            } else if let message, !message.isDeleted {
                selected.append(message)
            }
            guard !selected.isEmpty else { return (nil, nil, nil) }
            return (nil, nil, SelectionUpdate(selectedMessages: selected, messageAction: .forwardSelection))
            
        case .forwardSelection:
            // This handles when user is in forward selection mode and selects more messages
            var selected = selectedMessages ?? []
            if let mediaMessages = mediaGroupMessages {
                selected.append(contentsOf: mediaMessages.filter { !$0.isDeleted })
            } else if let message, !message.isDeleted {
                selected.append(message)
            }
            return (nil, nil, SelectionUpdate(selectedMessages: selected, messageAction: .forwardSelection))

        case .delete:
            var selected = selectedMessages ?? []
            if let mediaMessages = mediaGroupMessages {
                selected.append(contentsOf: mediaMessages.filter { !$0.isDeleted })
            } else if let message, !message.isDeleted {
                selected.append(message)
            }
            guard !selected.isEmpty else { return (nil, nil, nil) }
            return (nil, nil, SelectionUpdate(selectedMessages: selected, messageAction: action))
        }
    }

    static func toggleSelection(
        for message: MessageDataItem,
        selectedMessages: [MessageDataItem]?,
        messageAction: MessageMenuAction?
    ) -> SelectionUpdate {
        var selected = selectedMessages ?? []
        if let index = selected.firstIndex(where: { $0.id == message.id }) {
            selected.remove(at: index)
            if selected.isEmpty {
                return SelectionUpdate(selectedMessages: nil, messageAction: nil)
            }
            return SelectionUpdate(selectedMessages: selected, messageAction: messageAction)
        }
        selected.append(message)
        return SelectionUpdate(selectedMessages: selected, messageAction: messageAction)
    }

    static func isMessageSelected(_ message: MessageDataItem, in selectedMessages: [MessageDataItem]?) -> Bool {
        selectedMessages?.contains(where: { $0.id == message.id }) == true
    }

    static func isSelectionMode(messageAction: MessageMenuAction?) -> Bool {
        messageAction == .delete || messageAction == .forwardSelection
    }
}
