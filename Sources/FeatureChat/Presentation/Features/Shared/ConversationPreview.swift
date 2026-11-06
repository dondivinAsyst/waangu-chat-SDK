//
//  ConversationPreview.swift
//  FeatureChat
//
//  The inbox half of a row whose other half comes from Identity.
//

import Foundation

/// What a conversation contributes to a list row: the last thing said, when,
/// and how much of it is unread.
///
/// Channels and community groups are both drawn from two sources — Identity for
/// the name and the picture, the inbox for the activity — so the join happens
/// once, here.
struct ConversationPreview: Equatable {

    let text: String
    let messageType: MessageTypeProps?
    let time: String
    let unreadCount: Int

    static let empty = ConversationPreview(text: "", messageType: nil, time: "", unreadCount: 0)
}

extension ConversationPreview {

    /// Indexes discussions by conversation id, ready to be looked up by a row.
    static func index(_ discussions: [DiscussionChatItem]) -> [String: ConversationPreview] {
        var previews: [String: ConversationPreview] = [:]

        for discussion in discussions where !discussion.conversationId.isEmpty {
            previews[discussion.conversationId] = ConversationPreview(
                text: discussion.lastMessage.message.text,
                messageType: discussion.lastMessage.typeMessage,
                time: rowTime(discussion.lastMessage.createdAt),
                unreadCount: discussion.count
            )
        }

        return previews
    }

    /// Trailing time on a row: the clock for today, the localised "Yesterday",
    /// the date beyond that.
    static func rowTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        } else if calendar.isDateInYesterday(date) {
            // `.doesRelativeDateFormatting` is what produces the localised
            // "Yesterday" — hardcoding the word would ship English into four
            // locales.
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            formatter.doesRelativeDateFormatting = true
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }

        return formatter.string(from: date)
    }
}
