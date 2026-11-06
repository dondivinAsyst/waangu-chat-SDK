import XCTest
@testable import WaanguFeatureChat

/// `prependGeneration` is what tells the message list that an older page landed,
/// so it can restore the scroll anchor it took before requesting one.
///
/// The list used to infer this from the message count instead, and lost either
/// way: a read receipt rebuilds the timeline without changing the count, and an
/// inbound message changes the count without being a page. Whenever one of those
/// arrived while a page was in flight, the anchor was consumed by the wrong
/// update and the list jumped — usually all the way to the bottom.
///
/// These cases pin the one invariant that fix rests on: the counter moves for a
/// splice that actually added rows, and for nothing else.
@MainActor
final class ChatRoomPaginationSpliceTests: XCTestCase {

    private func message(_ code: String, at seconds: TimeInterval) -> MessageDataItem {
        MessageDataItem(
            codeMessage: code,
            message: MessageContent(text: code),
            createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func page(_ messages: [MessageDataItem], hasMore: Bool = true) -> ChatRoomPaginationResult {
        ChatRoomPaginationResult(
            messages: messages,
            allMediaMessages: [],
            oldestLoadedDate: messages.first?.createdAt,
            hasMore: hasMore
        )
    }

    /// Two messages already on screen, as after a first paint.
    private func loadedStore() async -> ChatRoomMessagesStore {
        let store = ChatRoomMessagesStore()
        await store.applyInitialPage(page([message("m10", at: 100), message("m11", at: 110)]))
        return store
    }

    // MARK: - The counter moves only for a real splice

    func test_firstPaintIsNotASplice() async {
        let store = await loadedStore()

        // The initial page is the anchor-free case: nothing was on screen to
        // hold still, so treating it as a splice would scroll a fresh room.
        XCTAssertEqual(store.prependGeneration, 0)
        XCTAssertEqual(store.messages.count, 2)
    }

    func test_pageThatAddsRowsBumpsTheGeneration() async {
        let store = await loadedStore()

        await store.applyPagination(page([message("m8", at: 80), message("m9", at: 90)]))

        XCTAssertEqual(store.prependGeneration, 1)
        XCTAssertEqual(store.messages.map(\.codeMessage), ["m8", "m9", "m10", "m11"])
    }

    func test_eachPageBumpsExactlyOnce() async {
        let store = await loadedStore()

        await store.applyPagination(page([message("m8", at: 80)]))
        await store.applyPagination(page([message("m7", at: 70)]))
        await store.applyPagination(page([message("m6", at: 60)]))

        XCTAssertEqual(store.prependGeneration, 3)
        XCTAssertEqual(store.messages.count, 5)
    }

    // MARK: - The counter stays put when nothing was spliced

    func test_emptyPageDoesNotBumpTheGeneration() async {
        let store = await loadedStore()

        await store.applyPagination(page([], hasMore: false))

        // Nothing moved above the window, so the anchor must survive for the
        // page that does land rather than being spent on this one.
        XCTAssertEqual(store.prependGeneration, 0)
        XCTAssertEqual(store.messages.count, 2)
    }

    func test_pageOfOnlyMessagesAlreadyHeldDoesNotBumpTheGeneration() async {
        let store = await loadedStore()

        await store.applyPagination(page([message("m10", at: 100), message("m11", at: 110)]))

        // A duplicate page leaves the timeline exactly as it was. Restoring a
        // scroll anchor here would move the list for no reason at all.
        XCTAssertEqual(store.prependGeneration, 0)
        XCTAssertEqual(store.messages.count, 2)
    }

    func test_partlyDuplicatePageBumpsOnceForTheRowsItAdded() async {
        let store = await loadedStore()

        await store.applyPagination(page([message("m9", at: 90), message("m10", at: 100)]))

        XCTAssertEqual(store.prependGeneration, 1)
        XCTAssertEqual(store.messages.map(\.codeMessage), ["m9", "m10", "m11"])
    }

    // MARK: - Other traffic never looks like a page

    func test_inboundMessageDoesNotBumpTheGeneration() async {
        let store = await loadedStore()

        // The case that used to break the anchor: the count grows, but this is
        // a new message arriving at the bottom, not an older page above.
        await store.applyObservation([
            message("m10", at: 100),
            message("m11", at: 110),
            message("m12", at: 120)
        ])

        XCTAssertEqual(store.prependGeneration, 0)
        XCTAssertEqual(store.messages.count, 3)
    }
}
