//
//  ChatRoomReactionCoordinator.swift
//  FeatureChat
//

import Foundation

/// Toggles emoji reactions on a message.
enum ChatRoomReactionCoordinator {

    static func toggledReactions(
        on message: MessageDataItem,
        reaction: Reaction,
        userId: String
    ) -> [ReactionItem] {
        let emoji = reaction.emoji
        var updatedReactions = message.reactions ?? []

        if let existingIndex = updatedReactions.firstIndex(where: { $0.userId == userId }) {
            if updatedReactions[existingIndex].reaction == emoji {
                updatedReactions.remove(at: existingIndex)
            } else {
                updatedReactions[existingIndex] = ReactionItem(userId: userId, reaction: emoji)
            }
        } else {
            updatedReactions.append(ReactionItem(userId: userId, reaction: emoji))
        }

        return updatedReactions
    }

    static func mqttReactionPayload(
        messageId: String,
        conversationId: String,
        senderId: String,
        emoji: String
    ) -> Data? {
        let payload: [String: Any] = [
            "type": "chat.message.reaction",
            "data": [
                "messageId": messageId,
                "conversationId": conversationId,
                "senderId": senderId,
                "emoji": emoji,
            ] as [String: Any],
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
