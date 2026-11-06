import XCTest
@testable import WaanguFeatureChat

final class ChatRoomMessageActionCoordinatorTests: XCTestCase {

    func test_copy_returnsPlainText() {
        let message = makeTextMessage(id: "m1", text: "Hello world")
        let row = MessageRow.message(message)

        let result = ChatRoomMessageActionCoordinator.handle(.copy, on: row, selectedMessages: nil)

        XCTAssertEqual(result.copyText, "Hello world")
        XCTAssertNil(result.replyMessage)
        XCTAssertNil(result.selection)
    }

    func test_reply_setsReplyRow() {
        let message = makeTextMessage(id: "m1", text: "Hi")
        let row = MessageRow.message(message)

        let result = ChatRoomMessageActionCoordinator.handle(.reply, on: row, selectedMessages: nil)

        XCTAssertNil(result.copyText)
        XCTAssertEqual(result.replyMessage, row)
        XCTAssertNil(result.selection)
    }

    func test_forward_entersSelectionModeWithSingleMessage() {
        let message = makeTextMessage(id: "m1", text: "Forward me")
        let row = MessageRow.message(message)

        let result = ChatRoomMessageActionCoordinator.handle(.forward, on: row, selectedMessages: nil)

        // Forward opens multi-selection (`.forwardSelection`) rather than
        // forwarding at once — see commit 102cc844.
        XCTAssertEqual(result.selection?.messageAction, .forwardSelection)
        XCTAssertEqual(result.selection?.selectedMessages?.map(\.codeMessage), ["m1"])
    }

    func test_forward_mediaGroupSelectsAllMessages() {
        let m1 = makeTextMessage(id: "m1", text: "")
        let m2 = makeTextMessage(id: "m2", text: "")
        let row = MessageRow.mediaGroup(idGroup: "g1", messages: [m1, m2])

        let result = ChatRoomMessageActionCoordinator.handle(.delete, on: row, selectedMessages: [])

        XCTAssertEqual(result.selection?.messageAction, .delete)
        XCTAssertEqual(result.selection?.selectedMessages?.map(\.codeMessage), ["m1", "m2"])
    }

    func test_toggleSelection_removesMessageAndClearsActionWhenEmpty() {
        let message = makeTextMessage(id: "m1", text: "x")
        let update = ChatRoomMessageActionCoordinator.toggleSelection(
            for: message,
            selectedMessages: [message],
            messageAction: .delete
        )

        XCTAssertNil(update.selectedMessages)
        XCTAssertNil(update.messageAction)
    }

    func test_isSelectionMode() {
        XCTAssertTrue(ChatRoomMessageActionCoordinator.isSelectionMode(messageAction: .forwardSelection))
        XCTAssertTrue(ChatRoomMessageActionCoordinator.isSelectionMode(messageAction: .delete))
        XCTAssertFalse(ChatRoomMessageActionCoordinator.isSelectionMode(messageAction: nil))
    }

    // MARK: - Helpers

    private func makeTextMessage(id: String, text: String) -> MessageDataItem {
        MessageDataItem(
            codeMessage: id,
            senderId: "sender",
            senderPhone: "111",
            senderName: "User",
            receiverId: "receiver",
            groupId: "",
            typeMessage: .TEXT,
            message: MessageContent(text: text),
            status: .SENT,
            createdAt: Date()
        )
    }
}
