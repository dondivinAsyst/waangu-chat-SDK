import XCTest
@testable import WaanguFeatureChat

final class ChatRoomGroupIntroCoordinatorTests: XCTestCase {

    func test_shouldShowIntro_onlyForGroupsNotYetDismissed() {
        XCTAssertTrue(ChatRoomGroupIntroCoordinator.shouldShowIntro(isGroup: true, hasBeenDismissed: false))
        XCTAssertFalse(ChatRoomGroupIntroCoordinator.shouldShowIntro(isGroup: true, hasBeenDismissed: true))
        XCTAssertFalse(ChatRoomGroupIntroCoordinator.shouldShowIntro(isGroup: false, hasBeenDismissed: false))
    }

    func test_shouldAutoDismiss_whenUserMessageExists() {
        let userMessage = makeTextMessage()
        XCTAssertTrue(
            ChatRoomGroupIntroCoordinator.shouldAutoDismiss(
                isGroup: true,
                hasBeenDismissed: false,
                messages: [userMessage]
            )
        )
        XCTAssertFalse(
            ChatRoomGroupIntroCoordinator.shouldAutoDismiss(
                isGroup: true,
                hasBeenDismissed: true,
                messages: [userMessage]
            )
        )
    }

    func test_ignoresGroupCreatedSystemMessage() {
        var system = makeTextMessage()
        system.typeMessage = .GROUP_CREATED
        XCTAssertFalse(
            ChatRoomGroupIntroCoordinator.shouldAutoDismiss(
                isGroup: true,
                hasBeenDismissed: false,
                messages: [system]
            )
        )
    }

    private func makeTextMessage() -> MessageDataItem {
        MessageDataItem(
            codeMessage: "m1",
            senderId: "sender",
            senderPhone: "111",
            senderName: "User",
            receiverId: "receiver",
            groupId: "g1",
            typeMessage: .TEXT,
            message: MessageContent(text: "hello"),
            status: .SENT,
            createdAt: Date()
        )
    }
}
