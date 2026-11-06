import XCTest
@testable import WaanguFeatureChat

final class GroupSenderRunResolverTests: XCTestCase {

    func test_returnsNothing_forDirectChat() {
        let sections = [makeSection(rows: [
            .message(makeMessage(id: "m1", senderId: "other-1")),
            .message(makeMessage(id: "m2", senderId: "other-1"))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: false)

        XCTAssertTrue(positions.isEmpty)
    }

    func test_marksOnlyTheEndsOfARun() {
        let sections = [makeSection(rows: [
            .message(makeMessage(id: "m1", senderId: "other-1")),
            .message(makeMessage(id: "m2", senderId: "other-1")),
            .message(makeMessage(id: "m3", senderId: "other-1"))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        XCTAssertEqual(positions["m1"], SenderRunPosition(isFirstOfRun: true, isLastOfRun: false))
        XCTAssertEqual(positions["m2"], SenderRunPosition(isFirstOfRun: false, isLastOfRun: false))
        XCTAssertEqual(positions["m3"], SenderRunPosition(isFirstOfRun: false, isLastOfRun: true))
    }

    func test_alternatingSenders_makeEveryRowItsOwnRun() {
        let sections = [makeSection(rows: [
            .message(makeMessage(id: "m1", senderId: "other-1")),
            .message(makeMessage(id: "m2", senderId: "other-2")),
            .message(makeMessage(id: "m3", senderId: "other-1"))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        for id in ["m1", "m2", "m3"] {
            XCTAssertEqual(
                positions[id],
                SenderRunPosition(isFirstOfRun: true, isLastOfRun: true),
                "row \(id)"
            )
        }
    }

    func test_checkpointBreaksARun() {
        let checkpoint = ChatActionItem(
            id: "cp-1",
            conversationId: "g1",
            actionType: .memberJoined,
            performedBy: "other-2",
            targetId: "other-2"
        )

        let sections = [makeSection(rows: [
            .message(makeMessage(id: "m1", senderId: "other-1")),
            .checkpoint(checkpoint),
            .message(makeMessage(id: "m2", senderId: "other-1"))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        XCTAssertNil(positions["cp-1"])
        XCTAssertEqual(positions["m1"], SenderRunPosition(isFirstOfRun: true, isLastOfRun: true))
        XCTAssertEqual(positions["m2"], SenderRunPosition(isFirstOfRun: true, isLastOfRun: true))
    }

    func test_groupEventMessageCarriesNoSenderIdentity() {
        let sections = [makeSection(rows: [
            .message(makeMessage(id: "m1", senderId: "other-1", type: .USER_ADDED_TO_GROUP))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        XCTAssertTrue(positions.isEmpty)
    }

    func test_runsDoNotSpanSections() {
        let sections = [
            makeSection(id: "2026-08-06", rows: [
                .message(makeMessage(id: "m1", senderId: "other-1"))
            ]),
            makeSection(id: "2026-08-07", rows: [
                .message(makeMessage(id: "m2", senderId: "other-1"))
            ])
        ]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        XCTAssertEqual(positions["m1"], SenderRunPosition(isFirstOfRun: true, isLastOfRun: true))
        XCTAssertEqual(positions["m2"], SenderRunPosition(isFirstOfRun: true, isLastOfRun: true))
    }

    func test_ownMessagesGetNoPosition() {
        let sections = [makeSection(rows: [
            .message(makeMessage(id: "m1", senderId: CurrentSessionInfo.shared.currentUid))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        XCTAssertNil(positions["m1"])
    }

    func test_mediaGroupRowTakesTheSenderOfItsFirstMessage() {
        let sections = [makeSection(rows: [
            .mediaGroup(idGroup: "group_1", messages: [
                makeMessage(id: "m1", senderId: "other-1", type: .IMAGE),
                makeMessage(id: "m2", senderId: "other-1", type: .IMAGE)
            ]),
            .message(makeMessage(id: "m3", senderId: "other-1"))
        ])]

        let positions = GroupSenderRunResolver.resolve(sections: sections, isGroup: true)

        XCTAssertEqual(positions["group_1"], SenderRunPosition(isFirstOfRun: true, isLastOfRun: false))
        XCTAssertEqual(positions["m3"], SenderRunPosition(isFirstOfRun: false, isLastOfRun: true))
    }

    // MARK: - Fixtures

    private func makeSection(id: String = "2026-08-07", rows: [MessageRow]) -> MessageSection {
        MessageSection(id: id, date: "Today", rows: rows)
    }

    private func makeMessage(
        id: String,
        senderId: String,
        type: MessageTypeProps = .TEXT
    ) -> MessageDataItem {
        MessageDataItem(
            codeMessage: id,
            senderId: senderId,
            senderPhone: "111",
            senderName: "Sender \(senderId)",
            receiverId: "conv",
            groupId: "g1",
            typeMessage: type,
            message: MessageContent(text: "hello"),
            status: .SENT,
            createdAt: Date()
        )
    }
}
