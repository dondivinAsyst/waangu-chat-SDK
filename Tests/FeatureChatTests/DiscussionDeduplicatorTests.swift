import XCTest
@testable import WaanguFeatureChat

/// The inbox shows one row per person, whatever the table holds.
final class DiscussionDeduplicatorTests: XCTestCase {

    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    private func row(
        id: String,
        serverId: String? = nil,
        userId: String = "",
        phone: String = "",
        name: String = "",
        text: String = "",
        at date: Date,
        unread: Int = 0,
        draft: String? = nil,
        isGroup: Bool = false
    ) -> DiscussionDeduplicator.Row {
        DiscussionDeduplicator.Row(
            conversation: ConversationModel(
                id: id,
                serverId: serverId,
                type: isGroup ? .group : .direct,
                lastMessageAt: date,
                createdAt: earlier
            ),
            item: DiscussionChatItem(
                lastMessage: MessageDataItem(
                    codeMessage: "\(id)-msg",
                    message: MessageContent(text: text),
                    createdAt: date
                ),
                conversationId: id,
                contact: ContactChannel(
                    userName: name,
                    phone: phone,
                    isBlocked: false,
                    isGroup: isGroup,
                    id: id,
                    userId: userId
                ),
                count: unread,
                draft: draft
            )
        )
    }

    // MARK: - Collapsing

    func test_twoRowsForOnePersonBecomeOne() {
        // The exact shape in the screenshot: the same peer stored twice, once
        // locally and once from the server.
        let local = row(id: "local", userId: "u1", name: "Dany", text: "Yooo lead", at: later)
        let synced = row(id: "synced", serverId: "srv", userId: "u1", name: "Dany", text: "Yooo", at: earlier)

        let collapsed = DiscussionDeduplicator.collapsed([local, synced])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.conversationId, "synced")
    }

    func test_collapsedRowShowsTheNewestMessageFromEitherHalf() {
        let local = row(id: "local", userId: "u1", text: "Yooo lead", at: later)
        let synced = row(id: "synced", serverId: "srv", userId: "u1", text: "Yooo", at: earlier)

        let collapsed = DiscussionDeduplicator.collapsed([local, synced])

        XCTAssertEqual(collapsed.first?.lastMessage.message.text, "Yooo lead")
    }

    func test_unreadCountsAreSummedNotMaxed() {
        // Each row holds different messages, so the number waiting from this
        // person is the total.
        let a = row(id: "a", userId: "u1", at: later, unread: 2)
        let b = row(id: "b", serverId: "srv", userId: "u1", at: earlier, unread: 3)

        XCTAssertEqual(DiscussionDeduplicator.collapsed([a, b]).first?.count, 5)
    }

    func test_aNamedRowLendsItsNameToTheNamelessWinner() {
        let nameless = row(id: "winner", serverId: "srv", userId: "u1", at: later)
        let named = row(id: "loser", userId: "u1", name: "Sarah", at: earlier)

        let collapsed = DiscussionDeduplicator.collapsed([nameless, named])

        XCTAssertEqual(collapsed.first?.contact?.userName, "Sarah")
    }

    func test_draftSurvivesTheRowThatLost() {
        let winner = row(id: "winner", serverId: "srv", userId: "u1", at: later)
        let loser = row(id: "loser", userId: "u1", at: earlier, draft: "half typed")

        XCTAssertEqual(DiscussionDeduplicator.collapsed([winner, loser]).first?.draft, "half typed")
    }

    // MARK: - Matching

    func test_sameNumberWrittenTwoWaysIsOnePerson() {
        // No account id on either row: the digits are all we have, and one row
        // is spaced while the other is not.
        let spaced = row(id: "a", phone: "+257 61 23 45 67", at: later)
        let plain = row(id: "b", phone: "+25761234567", at: earlier)

        XCTAssertEqual(DiscussionDeduplicator.collapsed([spaced, plain]).count, 1)
    }

    func test_differentPeopleAreLeftAlone() {
        let one = row(id: "a", userId: "u1", name: "Dany", at: later)
        let two = row(id: "b", userId: "u2", name: "Jakin", at: earlier)

        XCTAssertEqual(DiscussionDeduplicator.collapsed([one, two]).count, 2)
    }

    func test_groupsAreNeverCollapsedIntoEachOther() {
        // Groups carry no peer, and two groups are never the same conversation
        // however alike their rows look.
        let first = row(id: "g1", name: "Team", at: later, isGroup: true)
        let second = row(id: "g2", name: "Team", at: earlier, isGroup: true)

        XCTAssertEqual(DiscussionDeduplicator.collapsed([first, second]).count, 2)
    }

    func test_rowsWithNoPeerIdentityAreAllKept() {
        // Nothing identifies these, so nothing proves they are duplicates.
        let first = row(id: "a", at: later)
        let second = row(id: "b", at: earlier)

        XCTAssertEqual(DiscussionDeduplicator.collapsed([first, second]).count, 2)
    }

    func test_orderOfFirstAppearanceIsPreserved() {
        let a = row(id: "a", userId: "u1", at: later)
        let b = row(id: "b", userId: "u2", at: later)
        let aDuplicate = row(id: "a2", userId: "u1", at: earlier)

        let collapsed = DiscussionDeduplicator.collapsed([a, b, aDuplicate])

        XCTAssertEqual(collapsed.map(\.conversationId), ["a", "b"])
    }
}
