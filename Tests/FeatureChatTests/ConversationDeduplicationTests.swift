import XCTest
@testable import WaanguFeatureChat

/// The rule that decides which of two rows for one person the other folds into.
final class ConversationDeduplicationTests: XCTestCase {

    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    private func conversation(
        id: String,
        serverId: String? = nil,
        lastMessageAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> ConversationModel {
        ConversationModel(
            id: id,
            serverId: serverId,
            type: .direct,
            lastMessageAt: lastMessageAt,
            createdAt: createdAt
        )
    }

    func test_theRowTheServerKnowsWins() {
        // Even when the purely local row is the more recently active one: the
        // server's identity is the one that survives the next sync.
        let local = conversation(id: "local", lastMessageAt: later)
        let synced = conversation(id: "synced", serverId: "srv", lastMessageAt: earlier)

        XCTAssertEqual(
            ConversationDeduplicationService.survivor(among: [local, synced])?.id,
            "synced"
        )
    }

    func test_amongUnlinkedRowsTheMostRecentlyActiveWins() {
        let stale = conversation(id: "stale", lastMessageAt: earlier)
        let fresh = conversation(id: "fresh", lastMessageAt: later)

        XCTAssertEqual(
            ConversationDeduplicationService.survivor(among: [stale, fresh])?.id,
            "fresh"
        )
    }

    func test_rowWithNoActivityFallsBackToItsCreationDate() {
        let never = conversation(id: "never", lastMessageAt: nil, createdAt: later)
        let spoken = conversation(id: "spoken", lastMessageAt: earlier, createdAt: earlier)

        XCTAssertEqual(
            ConversationDeduplicationService.survivor(among: [never, spoken])?.id,
            "never"
        )
    }

    func test_tiesAreBrokenByTheOlderRow() {
        // Whichever thread has been here longest is the one with the history.
        let older = conversation(id: "older", lastMessageAt: later, createdAt: earlier)
        let newer = conversation(id: "newer", lastMessageAt: later, createdAt: later)

        XCTAssertEqual(
            ConversationDeduplicationService.survivor(among: [older, newer])?.id,
            "older"
        )
    }

    func test_selectionIsStableRegardlessOfInputOrder() {
        // A pass that ran twice used to be able to pick a different winner and
        // ping-pong the merge. Order must not matter.
        let a = conversation(id: "a", serverId: "srv", lastMessageAt: earlier)
        let b = conversation(id: "b", lastMessageAt: later)
        let c = conversation(id: "c", lastMessageAt: earlier)

        XCTAssertEqual(ConversationDeduplicationService.survivor(among: [a, b, c])?.id, "a")
        XCTAssertEqual(ConversationDeduplicationService.survivor(among: [c, b, a])?.id, "a")
        XCTAssertEqual(ConversationDeduplicationService.survivor(among: [b, a, c])?.id, "a")
    }

    func test_emptyInputHasNoSurvivor() {
        XCTAssertNil(ConversationDeduplicationService.survivor(among: []))
    }
}
