import XCTest
@testable import WaanguFeatureChat

final class DiscussionFilterCoordinatorTests: XCTestCase {

    /// The filter follows the unread badge in the list (`count > 0`), whoever
    /// sent the last message. Excluding "sent by me" was dropped in 83bc70a4: a
    /// conversation showing a badge must not vanish from the Unread filter.
    func test_unreadFilter_matchesUnreadBadge() {
        let unread = makeDiscussion(id: "1", count: 2, sentByMe: false)
        let read = makeDiscussion(id: "2", count: 0, sentByMe: false)
        let repliedWithUnread = makeDiscussion(id: "3", count: 1, sentByMe: true)

        let result = DiscussionFilterCoordinator.apply(
            .unread,
            to: [unread, read, repliedWithUnread],
            customLists: []
        )

        XCTAssertEqual(result.map(\.conversationId), ["1", "3"])
    }

    func test_allFilter_returnsEveryDiscussion() {
        let a = makeDiscussion(id: "a", count: 0, sentByMe: false)
        let b = makeDiscussion(id: "b", count: 1, sentByMe: false)

        let result = DiscussionFilterCoordinator.apply(.all, to: [a, b], customLists: [])

        XCTAssertEqual(result.count, 2)
    }

    func test_filterItems_includesAllWithCount() {
        let unread = makeDiscussion(id: "1", count: 2, sentByMe: false)
        let read = makeDiscussion(id: "2", count: 0, sentByMe: false)

        let items = DiscussionFilterCoordinator.filterItems(
            discussions: [unread, read],
            customLists: [DiscussionCustomList(name: "Work")]
        )

        XCTAssertEqual(items.first?.filter, .all)
        XCTAssertEqual(items.first?.count, 2)
        XCTAssertEqual(items.first(where: { $0.filter == .unread })?.count, 1)
        XCTAssertEqual(items.first(where: { $0.filter == .groups })?.count, 0)
        XCTAssertNotNil(items.first(where: {
            if case .customList(_, let name) = $0.filter { return name == "Work" }
            return false
        }))
    }

    func test_customListFilter_matchesMembership() {
        let a = makeDiscussion(id: "a", count: 0, sentByMe: false)
        let b = makeDiscussion(id: "b", count: 0, sentByMe: false)
        let lists = [DiscussionCustomList(id: "list-1", name: "Civ Deities", conversationIds: ["a"])]

        let result = DiscussionFilterCoordinator.apply(
            .customList(id: "list-1", name: "Civ Deities"),
            to: [a, b],
            customLists: lists
        )

        XCTAssertEqual(result.map(\.conversationId), ["a"])
    }

    private func makeDiscussion(id: String, count: Int, sentByMe: Bool) -> DiscussionChatItem {
        DiscussionChatItem(
            lastMessage: MessageDataItem(
                codeMessage: "m-\(id)",
                senderId: sentByMe ? CurrentSessionInfo.shared.currentUid : "other",
                senderPhone: "111",
                senderName: "User",
                receiverId: "r",
                groupId: "",
                typeMessage: .TEXT,
                message: MessageContent(text: "hi"),
                status: .SENT,
                createdAt: Date()
            ),
            conversationId: id,
            contact: ContactChannel(userName: "Test", phone: "1", isBlocked: false, id: id),
            count: count
        )
    }
}
