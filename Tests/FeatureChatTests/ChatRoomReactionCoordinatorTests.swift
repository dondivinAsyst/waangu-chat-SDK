import XCTest
@testable import WaanguFeatureChat

final class ChatRoomReactionCoordinatorTests: XCTestCase {

    func test_addsReactionWhenNoneExists() {
        let message = makeMessage(reactions: nil)
        let result = ChatRoomReactionCoordinator.toggledReactions(
            on: message,
            reaction: .like,
            userId: "user-1"
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].userId, "user-1")
        XCTAssertEqual(result[0].reaction, Reaction.like.emoji)
    }

    func test_removesReactionWhenSameEmojiTapped() {
        let existing = [ReactionItem(userId: "user-1", reaction: Reaction.like.emoji)]
        let message = makeMessage(reactions: existing)

        let result = ChatRoomReactionCoordinator.toggledReactions(
            on: message,
            reaction: .like,
            userId: "user-1"
        )

        XCTAssertTrue(result.isEmpty)
    }

    func test_replacesReactionWhenDifferentEmojiTapped() {
        let existing = [ReactionItem(userId: "user-1", reaction: Reaction.like.emoji)]
        let message = makeMessage(reactions: existing)

        let result = ChatRoomReactionCoordinator.toggledReactions(
            on: message,
            reaction: .heart,
            userId: "user-1"
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].reaction, Reaction.heart.emoji)
    }

    func test_mqttPayload_containsExpectedFields() {
        let data = ChatRoomReactionCoordinator.mqttReactionPayload(
            messageId: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            emoji: "👍"
        )

        XCTAssertNotNil(data)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "chat.message.reaction")
        let payload = json?["data"] as? [String: Any]
        XCTAssertEqual(payload?["messageId"] as? String, "msg-1")
        XCTAssertEqual(payload?["conversationId"] as? String, "conv-1")
        XCTAssertEqual(payload?["senderId"] as? String, "user-1")
        XCTAssertEqual(payload?["emoji"] as? String, "👍")
    }

    // MARK: - Helpers

    private func makeMessage(reactions: [ReactionItem]?) -> MessageDataItem {
        var message = MessageDataItem(
            codeMessage: "m1",
            senderId: "sender",
            senderPhone: "111",
            senderName: "User",
            receiverId: "receiver",
            groupId: "",
            typeMessage: .TEXT,
            message: MessageContent(text: "hi"),
            status: .SENT,
            createdAt: Date()
        )
        message.reactions = reactions
        return message
    }
}
