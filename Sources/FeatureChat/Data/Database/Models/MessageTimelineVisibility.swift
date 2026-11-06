//
//  MessageTimelineVisibility.swift
//  FeatureChat
//
//  Delete-for-me rows stay in SQLite but must not appear in timeline / last-message.
//  `isDeletedForAll` is JSON-only (not an indexed SQL column) — filter in memory.
//

import Foundation

enum MessageTimelineVisibility {
    /// Visible in room + chat-list preview: normal messages + delete-for-everyone placeholders.
    /// Never a conversation system record stored before those were kept out:
    /// it would read "CONVERSATION_CREATED" in the thread and the chat list.
    static func isVisible(_ model: MessageModel) -> Bool {
        (!model.isDeleted || model.isDeletedForAll)
            && !ConversationSystemRecord.isStoredRecord(model)
    }

    static func filterVisible(_ models: [MessageModel]) -> [MessageModel] {
        models.filter(isVisible)
    }

    /// Newest timeline-visible message (skips delete-for-me).
    static func newestVisible(in models: [MessageModel]) -> MessageModel? {
        models.first(where: isVisible)
    }
}
