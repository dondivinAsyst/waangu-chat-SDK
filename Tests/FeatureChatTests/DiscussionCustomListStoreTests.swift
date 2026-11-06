import XCTest
@testable import WaanguFeatureChat

final class DiscussionCustomListStoreTests: XCTestCase {

    private let storageKey = "featureChat.discussionCustomLists"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: "featureChat.discussionCustomListsSeeded")
        super.tearDown()
    }

    func test_deleteList_removesListFromStorage() {
        DiscussionCustomListStore.save([
            DiscussionCustomList(id: "work", name: "Work"),
            DiscussionCustomList(id: "personal", name: "Personal")
        ])

        XCTAssertEqual(DiscussionCustomListStore.deleteList(listId: "work"), "Work")
        XCTAssertEqual(DiscussionCustomListStore.load().map(\.name), ["Personal"])
        XCTAssertNil(DiscussionCustomListStore.deleteList(listId: "missing"))
    }

    func test_addAndRemoveConversation_updatesMembership() {
        let list = DiscussionCustomList(id: "work", name: "Work")
        DiscussionCustomListStore.save([list])

        XCTAssertTrue(DiscussionCustomListStore.addConversation("chat-1", toListId: "work"))
        XCTAssertTrue(DiscussionCustomListStore.isConversation("chat-1", inListId: "work"))
        XCTAssertFalse(DiscussionCustomListStore.addConversation("chat-1", toListId: "work"))

        XCTAssertTrue(DiscussionCustomListStore.removeConversation("chat-1", fromListId: "work"))
        XCTAssertFalse(DiscussionCustomListStore.isConversation("chat-1", inListId: "work"))
        XCTAssertFalse(DiscussionCustomListStore.removeConversation("chat-1", fromListId: "work"))
    }
}
