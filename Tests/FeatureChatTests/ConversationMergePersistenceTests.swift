import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

/// Exercises the merge against a real SQLite store.
///
/// The questions worth answering here are not about the Swift: they are whether
/// the merge is actually *written down* — so the work happens once instead of on
/// every fetch — and whether a second pass over already-merged data does nothing.
final class ConversationMergePersistenceTests: XCTestCase {

    private let me = "me"
    private let peer = "peer-1"

    private func makeStore() async -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(
                engine: .sqlite,
                migrationSteps: ChatDatabaseRegistration.migrationSteps
            )
        )
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func makeService(_ store: any DatabaseRepositoryProtocol) -> ConversationDeduplicationService {
        ConversationDeduplicationService(database: store, currentUserId: { [me] in me })
    }

    /// A conversation with one peer participant and one message in it.
    private func seedConversation(
        id: String,
        serverId: String?,
        messageId: String,
        at date: Date,
        unread: Int,
        in store: any DatabaseRepositoryProtocol
    ) async throws {
        try await store.save(
            ConversationModel(
                id: id,
                serverId: serverId,
                type: .direct,
                lastMessageAt: date,
                unreadCount: unread,
                createdAt: date
            )
        )
        try await store.save(
            ConversationParticipantModel(
                id: "\(id)-participant",
                conversationId: id,
                userId: peer,
                contactId: nil,
                phone: "+25761234567",
                role: .member,
                displayName: "Dany",
                avatarURL: nil,
                customColor: nil,
                joinedAt: date,
                addedByUserId: nil,
                leftAt: nil,
                removedByUserId: nil,
                leaveReason: nil,
                createdAt: date,
                updatedAt: date
            )
        )
        try await store.save(
            MessageModel(
                id: messageId,
                conversationId: id,
                senderId: peer,
                senderName: "Dany",
                type: .text,
                timestamp: date
            )
        )
    }

    private func clearConversations(in store: any DatabaseRepositoryProtocol) async throws {
        for conversation in try await store.fetch(ConversationModel.self, query: nil) {
            try await store.delete(ConversationModel.self, id: conversation.id)
        }
    }

    // MARK: - The merge is written down

    func test_localDuplicateIsMergedAwayAndItsHistoryKept() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        // The pair from the screenshot: one row from the server, one minted
        // locally when the first message was sent.
        try await seedConversation(id: "synced", serverId: "srv", messageId: "m-first", at: old, unread: 1, in: store)
        try await seedConversation(id: "local", serverId: nil, messageId: "m-last", at: recent, unread: 2, in: store)

        let outcome = try await makeService(store).run()

        XCTAssertEqual(outcome.mergedConversations, 1)
        XCTAssertEqual(outcome.aliasedServerRows, 0, "a purely local row is deleted, not aliased")

        // The local row is gone from storage — not filtered at read time.
        let remaining = try await store.fetch(ConversationModel.self, query: nil)
        XCTAssertEqual(remaining.map(\.id), ["synced"])

        // Both ends of the history moved: the first message and the last.
        let messages = try await store.fetch(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string("synced")))
        )
        XCTAssertEqual(Set(messages.map(\.id)), ["m-first", "m-last"])
    }

    func test_mergedRowCarriesTheSummedUnreadAndTheNewerActivity() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        try await seedConversation(id: "synced", serverId: "srv", messageId: "m1", at: old, unread: 1, in: store)
        try await seedConversation(id: "local", serverId: nil, messageId: "m2", at: recent, unread: 2, in: store)

        _ = try await makeService(store).run()

        let survivor = try await store.fetchOne(ConversationModel.self, id: "synced")
        XCTAssertEqual(survivor?.unreadCount, 3)
        XCTAssertEqual(survivor?.lastMessageAt, recent)
    }

    // MARK: - Rows the server still owns

    func test_serverOwnedDuplicateIsKeptAsAnAliasPointingAtTheSurvivor() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        try await seedConversation(id: "srv-a", serverId: "srv-a", messageId: "m1", at: recent, unread: 0, in: store)
        try await seedConversation(id: "srv-b", serverId: "srv-b", messageId: "m2", at: old, unread: 0, in: store)

        let outcome = try await makeService(store).run()

        XCTAssertEqual(outcome.aliasedServerRows, 1)

        // Kept, because the next sync would recreate it — but emptied and
        // pointed at the thread that survived.
        let alias = try await store.fetchOne(ConversationModel.self, id: "srv-b")
        XCTAssertEqual(alias?.mergedIntoId, "srv-a")

        let messages = try await store.fetch(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string("srv-a")))
        )
        XCTAssertEqual(Set(messages.map(\.id)), ["m1", "m2"])
    }

    func test_anAliasRowIsNeverMergedAgain() async throws {
        // The alias stays in the table, so without skipping it every later pass
        // would re-do this merge — the exact "same activity every time" this is
        // meant to avoid.
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        try await seedConversation(id: "srv-a", serverId: "srv-a", messageId: "m1", at: recent, unread: 0, in: store)
        try await seedConversation(id: "srv-b", serverId: "srv-b", messageId: "m2", at: old, unread: 0, in: store)

        let service = makeService(store)
        _ = try await service.run()
        let second = try await service.run()

        XCTAssertEqual(second.mergedConversations, 0)
        XCTAssertEqual(second.aliasedServerRows, 0)
    }

    // MARK: - Doing it twice changes nothing

    func test_secondPassOverMergedDataDoesNothing() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        try await seedConversation(id: "synced", serverId: "srv", messageId: "m1", at: old, unread: 1, in: store)
        try await seedConversation(id: "local", serverId: nil, messageId: "m2", at: recent, unread: 2, in: store)

        let service = makeService(store)
        _ = try await service.run()
        let second = try await service.run()

        XCTAssertEqual(second.mergedConversations, 0)
        XCTAssertEqual(second.movedMessages, 0)

        // And the unread count was not summed a second time.
        let survivor = try await store.fetchOne(ConversationModel.self, id: "synced")
        XCTAssertEqual(survivor?.unreadCount, 3)
    }

    /// The pair from the screenshot, identified two different ways.
    ///
    /// The locally created row stored the peer's *phone* in the `user_id`
    /// column; the synced row holds a real account id. Keyed on a single value
    /// these never matched, and the duplicate stayed on screen.
    func test_rowsIdentifiedByPhoneAndByAccountIdAreStillOnePerson() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)

        try await seedConversation(id: "synced", serverId: "srv", messageId: "m1", at: old, unread: 0, in: store)
        // The local half: no account id anywhere, the number standing in for it.
        try await store.save(
            ConversationModel(id: "local", type: .direct, lastMessageAt: recent, createdAt: recent)
        )
        try await store.save(
            ConversationParticipantModel(
                id: "local-participant",
                conversationId: "local",
                userId: "+257 61 23 45 67",
                phone: "+257 61 23 45 67",
                displayName: "Dany",
                joinedAt: recent,
                createdAt: recent,
                updatedAt: recent
            )
        )

        let outcome = try await makeService(store).run()

        XCTAssertEqual(outcome.mergedConversations, 1)
        let remaining = try await store.fetch(ConversationModel.self, query: nil).map(\.id)
        XCTAssertEqual(remaining, ["synced"])
    }

    /// The harder half of the same problem: the two rows share *nothing*.
    ///
    /// `PeerInfoDTO.phone` is optional and often absent, so the synced row can
    /// hold an account id and no number while the local row holds a number and
    /// no account id. The address book is the only thing that knows they are the
    /// same person.
    func test_theAddressBookLinksRowsThatShareNoIdentityDirectly() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)

        try await store.save(
            ContactModel(id: "c1", userId: peer, phone: "+25761234567", name: "Dany")
        )

        // Synced: an account id, no number.
        try await store.save(
            ConversationModel(id: "synced", serverId: "srv", type: .direct, lastMessageAt: old, createdAt: old)
        )
        try await store.save(
            ConversationParticipantModel(
                id: "synced-participant",
                conversationId: "synced",
                userId: peer,
                phone: "",
                displayName: "Dany",
                joinedAt: old,
                createdAt: old,
                updatedAt: old
            )
        )

        // Local: a number, no account id.
        try await store.save(
            ConversationModel(id: "local", type: .direct, lastMessageAt: recent, createdAt: recent)
        )
        try await store.save(
            ConversationParticipantModel(
                id: "local-participant",
                conversationId: "local",
                userId: "",
                phone: "+257 61 23 45 67",
                displayName: "Dany",
                joinedAt: recent,
                createdAt: recent,
                updatedAt: recent
            )
        )

        let outcome = try await makeService(store).run()

        XCTAssertEqual(outcome.mergedConversations, 1)
        let remaining = try await store.fetch(ConversationModel.self, query: nil).map(\.id)
        XCTAssertEqual(remaining, ["synced"])
    }

    func test_conversationsWithDifferentPeopleAreNeverMerged() async throws {
        let store = await makeStore()
        try await clearConversations(in: store)

        let date = Date(timeIntervalSince1970: 1_000)
        try await seedConversation(id: "a", serverId: "srv-a", messageId: "m1", at: date, unread: 0, in: store)

        try await store.save(ConversationModel(id: "b", serverId: "srv-b", type: .direct, lastMessageAt: date, createdAt: date))
        try await store.save(
            ConversationParticipantModel(
                id: "b-participant",
                conversationId: "b",
                userId: "someone-else",
                contactId: nil,
                phone: "+25799999999",
                role: .member,
                displayName: "Jakin",
                avatarURL: nil,
                customColor: nil,
                joinedAt: date,
                addedByUserId: nil,
                leftAt: nil,
                removedByUserId: nil,
                leaveReason: nil,
                createdAt: date,
                updatedAt: date
            )
        )

        let outcome = try await makeService(store).run()

        XCTAssertEqual(outcome.mergedConversations, 0)
        let stored = try await store.fetch(ConversationModel.self, query: nil)
        XCTAssertEqual(stored.count, 2)
    }
}
