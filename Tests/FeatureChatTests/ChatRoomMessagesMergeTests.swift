import XCTest
@testable import WaanguFeatureChat

/// A message can reach the timeline by two routes at once — merged in when a
/// call ends, and reloaded from the database that already stored it. Before this
/// was de-duplicated the bubble rendered twice and anything keying messages by
/// `codeMessage` crashed on the repeated key.
final class ChatRoomMessagesMergeTests: XCTestCase {

    private func message(
        _ code: String,
        text: String = "",
        at seconds: TimeInterval = 0
    ) -> MessageDataItem {
        MessageDataItem(
            codeMessage: code,
            message: MessageContent(text: text),
            createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    func test_mergingTheSameMessageTwiceKeepsOneEntry() {
        let existing = [message("call-1", text: "Voice call", at: 10)]
        let incoming = [message("call-1", text: "Voice call", at: 10)]

        let merged = ChatRoomMessagesStore.merged(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.codeMessage, "call-1")
    }

    /// The incoming copy is the fresher one, so it replaces what was held.
    func test_incomingReplacesTheExistingCopy() {
        let existing = [message("m1", text: "before", at: 5)]
        let incoming = [message("m1", text: "after", at: 5)]

        let merged = ChatRoomMessagesStore.merged(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.message.text, "after")
    }

    func test_distinctMessagesAreAllKept() {
        let existing = [message("m1", at: 1), message("m2", at: 2)]
        let incoming = [message("m3", at: 3)]

        let merged = ChatRoomMessagesStore.merged(existing: existing, incoming: incoming)

        XCTAssertEqual(Set(merged.map(\.codeMessage)), ["m1", "m2", "m3"])
    }

    /// Blank codes carry no identity, so they cannot be collapsed into one
    /// another — that would silently delete messages.
    func test_messagesWithoutACodeAreNotCollapsed() {
        let existing = [message("", text: "one", at: 1)]
        let incoming = [message("", text: "two", at: 2)]

        let merged = ChatRoomMessagesStore.merged(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.count, 2)
    }

    /// The call record this device writes is filed under the server's `callId`,
    /// so if the backend ever delivers its own copy of the same call it replaces
    /// the local one rather than adding a second bubble.
    func test_serverCopyOfACallReplacesTheLocalOne() {
        let localCall = message("srv-call-1", text: "Missed voice call", at: 20)
        let serverCall = message("srv-call-1", text: "Voice call · 00:42", at: 20)

        let merged = ChatRoomMessagesStore.merged(
            existing: [localCall],
            incoming: [serverCall]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.message.text, "Voice call · 00:42")
    }

    /// The failure this guards against: a call filed under a client-invented id
    /// cannot be matched to the server's copy, so both survive.
    func test_differentIdsForTheSameCallBothSurvive() {
        let localCall = message("client-room-uuid", text: "Missed voice call", at: 20)
        let serverCall = message("server-call-uuid", text: "Voice call · 00:42", at: 20)

        let merged = ChatRoomMessagesStore.merged(
            existing: [localCall],
            incoming: [serverCall]
        )

        XCTAssertEqual(merged.count, 2, "mismatched ids cannot be reconciled")
    }

    func test_mergingIntoAnEmptyTimelineKeepsEverything() {
        let merged = ChatRoomMessagesStore.merged(
            existing: [],
            incoming: [message("m1", at: 1), message("m2", at: 2)]
        )
        XCTAssertEqual(merged.count, 2)
    }
}
