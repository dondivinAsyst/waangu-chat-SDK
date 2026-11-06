import XCTest
@testable import WaanguFeatureChat

/// Reactions are ephemeral by contract (§16.2): they animate briefly and are
/// never written anywhere. Expiry is driven by an injected date so the test does
/// not have to wait for it.
final class CallReactionFeedTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    func test_addKeepsReaction() {
        var feed = CallReactionFeed()
        feed.add(peerId: "userA", emoji: "👏", at: start)
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items.first?.emoji, "👏")
        XCTAssertEqual(feed.items.first?.peerId, "userA")
    }

    func test_pruneDropsExpiredOnly() {
        var feed = CallReactionFeed()
        feed.add(peerId: "userA", emoji: "👏", at: start)
        feed.add(peerId: "userB", emoji: "🔥", at: start.addingTimeInterval(2))

        feed.prune(now: start.addingTimeInterval(2.6))

        XCTAssertEqual(feed.items.map(\.peerId), ["userB"])
    }

    func test_pruneKeepsEverythingBeforeTtl() {
        var feed = CallReactionFeed()
        feed.add(peerId: "userA", emoji: "👏", at: start)
        feed.prune(now: start.addingTimeInterval(1))
        XCTAssertEqual(feed.items.count, 1)
    }

    /// Several people can react at once, and one person can react twice — each
    /// is its own badge.
    func test_multipleReactionsCoexist() {
        var feed = CallReactionFeed()
        feed.add(peerId: "userA", emoji: "👏", at: start)
        feed.add(peerId: "userA", emoji: "🎉", at: start)
        XCTAssertEqual(feed.items.count, 2)
    }

    func test_removeAllClearsFeed() {
        var feed = CallReactionFeed()
        feed.add(peerId: "userA", emoji: "👏", at: start)
        feed.removeAll()
        XCTAssertTrue(feed.items.isEmpty)
    }

    func test_paletteMatchesContract() {
        XCTAssertEqual(CallReactionFeed.palette, ["👍", "❤️", "😂", "😮", "😢", "👏", "🎉", "🔥"])
    }
}
