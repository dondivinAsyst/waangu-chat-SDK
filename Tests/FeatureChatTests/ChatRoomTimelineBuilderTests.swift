import XCTest
@testable import WaanguFeatureChat

final class ChatRoomTimelineBuilderTests: XCTestCase {

    func test_hidesJoinRequestCheckpoint_forNonAdmin() {
        let actions = [
            ChatActionItem(
                conversationId: "g1",
                actionType: .joinRequestReceived,
                performedBy: "user-2",
                targetId: "req-1"
            )
        ]

        let filtered = ChatRoomTimelineBuilder.filteredTimelineActions(
            from: actions,
            shouldShowGroupIntroHeader: false,
            isGroupAdmin: false
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    /// Media are grouped by the batch they were sent in, not by adjacency.
    ///
    /// Since 7da1c681 a grid is built from an explicit `mediaBatchId` — one
    /// multi-select send. Two photos sent one after the other are two sends, and
    /// merging them by direction showed them as a single album they never were.
    func test_groupsImagesSentInTheSameBatch_only() {
        var sent1 = makeImageMessage(id: "m1", direction: .sent, dayOffset: 0)
        var sent2 = makeImageMessage(id: "m2", direction: .sent, dayOffset: 1)
        sent1.message.mediaBatchId = "batch-1"
        sent2.message.mediaBatchId = "batch-1"
        let loneImage = makeImageMessage(id: "m3", direction: .sent, dayOffset: 2)

        var builder = ChatRoomTimelineBuilder()
        let sections = builder.build(
            ChatRoomTimelineInput(
                messages: [sent1, sent2, loneImage],
                chatActions: [],
                shouldShowGroupIntroHeader: false,
                isGroupAdmin: true,
                groupIntroContent: nil
            )
        )

        let rows = sections.flatMap(\.rows)
        let mediaGroups = rows.compactMap { row -> [MessageDataItem]? in
            if case .mediaGroup(_, let messages) = row { return messages }
            return nil
        }
        let singles = rows.compactMap { row -> String? in
            if case .message(let message) = row { return message.codeMessage }
            return nil
        }

        XCTAssertEqual(mediaGroups.map { $0.map(\.codeMessage) }, [["m1", "m2"]])
        XCTAssertEqual(singles, ["m3"], "An image without a batch is its own bubble, even next to a batch")
        XCTAssertEqual(builder.photoCodeToGroupId["m1"], builder.photoCodeToGroupId["m2"])
        XCTAssertNil(builder.photoCodeToGroupId["m3"])
    }

    func test_prependsGroupIntroWhenRequested() {
        let intro = GroupChatIntroContent(
            groupName: "Test Group",
            description: nil,
            memberCount: 3,
            avatarUrl: nil,
            createdByCurrentUser: true,
            canAddMembers: true,
            canShowInviteLink: true
        )

        var builder = ChatRoomTimelineBuilder()
        let sections = builder.build(
            ChatRoomTimelineInput(
                messages: [],
                chatActions: [],
                shouldShowGroupIntroHeader: true,
                isGroupAdmin: true,
                groupIntroContent: intro
            )
        )

        XCTAssertEqual(sections.count, 1)
        // B61 — l'avis E2EE n'apparaît que si l'app a le droit de l'affirmer.
        let expectsBanner = ChatEncryptionClaim.messagesAreEndToEndEncrypted
        XCTAssertEqual(sections[0].rows.count, expectsBanner ? 2 : 1)
        XCTAssertEqual(sections[0].rows.contains(.encryptionBanner), expectsBanner)
        if case .groupIntro(let content) = sections[0].rows.last {
            XCTAssertEqual(content.groupName, "Test Group")
        } else {
            XCTFail("Expected group intro row")
        }
    }

    // MARK: - Group events

    func test_rendersGroupEventMessageAsCheckpoint() {
        var builder = ChatRoomTimelineBuilder()
        let sections = builder.build(
            ChatRoomTimelineInput(
                messages: [makeGroupEvent(id: "e1", type: .USER_ADDED_TO_GROUP, targetId: "userC")],
                chatActions: [],
                shouldShowGroupIntroHeader: false,
                isGroupAdmin: true,
                groupIntroContent: nil
            )
        )

        let checkpoints = sections.flatMap(\.rows).compactMap { row -> ChatActionItem? in
            if case .checkpoint(let action) = row { return action }
            return nil
        }
        XCTAssertEqual(checkpoints.count, 1)
        XCTAssertEqual(checkpoints.first?.actionType, .memberAdded)
        XCTAssertEqual(checkpoints.first?.targetId, "userC")
        XCTAssertEqual(checkpoints.first?.id, "e1")
    }

    /// A system record is never a bubble, whatever else is true of it. Deletion was
    /// decided before the event kind, so a deleted group event rendered as a
    /// "message was deleted" bubble.
    func test_deletedGroupEventIsStillACheckpoint() {
        var message = makeGroupEvent(id: "e1", type: .USER_LEFT_GROUP, targetId: "userC")
        message.isDeleted = true

        var builder = ChatRoomTimelineBuilder()
        let rows = builder.build(
            ChatRoomTimelineInput(
                messages: [message],
                chatActions: [],
                shouldShowGroupIntroHeader: false,
                isGroupAdmin: true,
                groupIntroContent: nil
            )
        ).flatMap(\.rows)

        XCTAssertEqual(rows.count, 1)
        guard case .checkpoint = rows[0] else {
            return XCTFail("expected a checkpoint, got \(rows[0])")
        }
    }

    /// Every group event type, in one place: none of them may produce a bubble.
    func test_noGroupEventProducesAMessageRow() {
        let types: [MessageTypeProps] = [
            .GROUP_UPDATED, .USER_ADDED_TO_GROUP, .USER_LEFT_GROUP,
            .USER_REMOVED_FROM_GROUP, .USER_PROMOTED_TO_ADMIN, .USER_DEMOTED_FROM_ADMIN
        ]

        for type in types {
            var builder = ChatRoomTimelineBuilder()
            let rows = builder.build(
                ChatRoomTimelineInput(
                    messages: [makeGroupEvent(id: "e-\(type.rawValue)", type: type, targetId: "userC")],
                    chatActions: [],
                    shouldShowGroupIntroHeader: false,
                    isGroupAdmin: true,
                    groupIntroContent: nil
                )
            ).flatMap(\.rows)

            XCTAssertEqual(rows.count, 1, "\(type.rawValue)")
            if case .message = rows.first {
                XCTFail("\(type.rawValue) rendered as a bubble")
            }
        }
    }

    /// The actor records the change locally for instant feedback, then the server
    /// sends the same change back as a message. Only one of them may reach the
    /// timeline, or the actor sees every group change twice.
    func test_dropsLocalActionWhenServerSendsTheSameEvent() {
        let now = Date()
        let local = ChatActionItem(
            conversationId: "g1",
            actionType: .memberRemoved,
            performedBy: "me",
            targetId: "userC",
            timestamp: now
        )
        let fromServer = makeGroupEvent(
            id: "e1",
            type: .USER_REMOVED_FROM_GROUP,
            targetId: "userC",
            createdAt: now.addingTimeInterval(3)
        )

        let kept = ChatRoomTimelineBuilder.droppingLocalEchoes(of: [fromServer], from: [local])
        XCTAssertTrue(kept.isEmpty)
    }

    func test_keepsLocalActionWhenServerEventIsADifferentChange() {
        let now = Date()
        let local = ChatActionItem(
            conversationId: "g1",
            actionType: .memberRemoved,
            performedBy: "me",
            targetId: "userC",
            timestamp: now
        )
        let otherMember = makeGroupEvent(
            id: "e1",
            type: .USER_REMOVED_FROM_GROUP,
            targetId: "userD",
            createdAt: now
        )

        let kept = ChatRoomTimelineBuilder.droppingLocalEchoes(of: [otherMember], from: [local])
        XCTAssertEqual(kept.count, 1)
    }

    // MARK: - Helpers

    private func makeGroupEvent(
        id: String,
        type: MessageTypeProps,
        targetId: String,
        createdAt: Date = Date()
    ) -> MessageDataItem {
        MessageDataItem(
            codeMessage: id,
            senderId: "userA",
            senderPhone: "111",
            senderName: "Aline",
            receiverId: "",
            groupId: "g1",
            typeMessage: type,
            message: MessageContent(
                text: "",
                groupEvent: GroupEventContent(
                    eventType: type.rawValue,
                    targetUserId: targetId,
                    targetName: "JAKIN IRISA",
                    groupTitle: "Famille"
                )
            ),
            status: .DELIVERED,
            createdAt: createdAt
        )
    }

    private func makeImageMessage(id: String, direction: MessageDirection, dayOffset: TimeInterval) -> MessageDataItem {
        MessageDataItem(
            codeMessage: id,
            senderId: direction == .sent ? "me" : "them",
            senderPhone: "111",
            senderName: "User",
            receiverId: "conv",
            groupId: "",
            typeMessage: .IMAGE,
            message: MessageContent(text: ""),
            status: .SENT,
            createdAt: Date().addingTimeInterval(dayOffset)
        )
    }
}
