//
//  ArchiveOrderTests.swift
//  FeatureChatTests
//
//  Archiving or unarchiving a conversation puts it at its place by last-message
//  date. It used to be appended, and the list refresh ignores order changes, so
//  the conversation stayed last.
//

import XCTest
@testable import WaanguFeatureChat

@MainActor
final class ArchiveOrderTests: XCTestCase {

    private func discussion(_ id: String, minutesAgo: Double) -> DiscussionChatItem {
        DiscussionChatItem(
            lastMessage: MessageDataItem(
                codeMessage: "m-\(id)",
                senderId: "other",
                senderPhone: "111",
                senderName: "User",
                receiverId: "r",
                groupId: "",
                typeMessage: .TEXT,
                message: MessageContent(text: "hi"),
                status: .SENT,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
            ),
            conversationId: id,
            contact: ContactChannel(userName: "Test", phone: "1", isBlocked: false, id: id),
            count: 0
        )
    }

    func test_aConversation_goesBackToItsPlaceByDate() {
        var list = [discussion("new", minutesAgo: 1), discussion("old", minutesAgo: 60)]
        ChannelTabViewModel.insertByRecency(discussion("middle", minutesAgo: 10), into: &list)
        XCTAssertEqual(list.map(\.conversationId), ["new", "middle", "old"])
    }

    func test_theMostRecentConversation_goesFirst() {
        var list = [discussion("a", minutesAgo: 5), discussion("b", minutesAgo: 30)]
        ChannelTabViewModel.insertByRecency(discussion("latest", minutesAgo: 0), into: &list)
        XCTAssertEqual(list.first?.conversationId, "latest")
    }

    func test_theOldestConversation_goesLast_andAnEmptyListTakesIt() {
        var list = [discussion("a", minutesAgo: 5)]
        ChannelTabViewModel.insertByRecency(discussion("oldest", minutesAgo: 500), into: &list)
        XCTAssertEqual(list.map(\.conversationId), ["a", "oldest"])

        var empty: [DiscussionChatItem] = []
        ChannelTabViewModel.insertByRecency(discussion("only", minutesAgo: 1), into: &empty)
        XCTAssertEqual(empty.map(\.conversationId), ["only"])
    }
}
