import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Group lifecycle events arrive on the same inbox as messages and are meant to
/// travel the message path from there. These tests pin the rewrite that gets them
/// onto it: the payload names its actor differently in every event and carries no
/// message id, and `InboundMessageDTO` refuses to decode without either.
final class GroupSystemEventTests: XCTestCase {

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func decoded(_ object: [String: Any]) -> InboundMessageDTO? {
        guard let event = ChatMqttEventParser.parse(data: json(object)),
              let payload = event.payload?.rawData
        else { return nil }
        return try? JSONDecoder().decode(InboundMessageDTO.self, from: payload)
    }

    private let participants: [[String: Any]] = [
        ["userId": "userA", "username": "Aline", "phone": "0601", "role": "OWNER"],
        ["userId": "userC", "username": "JAKIN IRISA", "phone": "098741201", "role": "MEMBER"]
    ]

    /// The live shape: an ordinary `MESSAGE_SENT` envelope whose sender is the
    /// literal `"system"`, carrying the real event nested in `content` as an
    /// object rather than the JSON string ordinary messages send.
    private func wrapped(
        eventType: String,
        content extra: [String: Any] = [:]
    ) -> [String: Any] {
        var content: [String: Any] = [
            "eventType": eventType,
            "conversationId": "conv-1",
            "conversationType": "GROUP",
            "groupId": "conv-1",
            "title": "tes",
            "createdAt": 1_786_032_576_326,
            "participants": participants
        ]
        content.merge(extra) { _, new in new }

        return [
            "eventType": "MESSAGE_SENT",
            "payload": [
                "codeMessage": "57939c1f-1734-4d1a-bcd2-6fe706cdfc64",
                "senderId": "system",
                "senderName": "System",
                "senderPhone": "",
                "conversationId": "conv-1",
                "groupId": "conv-1",
                "content": content,
                "typeMessage": "SYSTEM",
                "isMessageSystem": true,
                "status": "UNREAD",
                "sentAt": "2026-08-06T16:09:36.340229400Z",
                "eventType": "MESSAGE_SENT"
            ]
        ]
    }

    /// Pull-events and the inbox summary build `InboundMessageDTO` straight from
    /// the server with no parser in between — nothing rewrites `typeMessage`.
    private func withoutParser(_ payload: [String: Any]) -> InboundMessageDTO? {
        try? JSONDecoder().decode(InboundMessageDTO.self, from: json(payload))
    }

    private func payloadOnly(
        eventType: String,
        content extra: [String: Any] = [:]
    ) -> [String: Any] {
        wrapped(eventType: eventType, content: extra)["payload"] as? [String: Any] ?? [:]
    }

    // MARK: - The live shape

    /// `typeMessage` now carries the event kind and `senderId` the real actor, so
    /// nothing has to be inferred. The content still arrives as a nested object.
    private func live(
        _ typeMessage: String,
        text: String = "",
        targets: [[String: Any]] = [],
        content extra: [String: Any] = [:],
        senderId: String = "645a3503ddb88a00085da11b",
        senderName: String = "Alice"
    ) -> [String: Any] {
        var content: [String: Any] = ["text": text, "targetUsers": targets]
        content.merge(extra) { _, new in new }
        return [
            "codeMessage": "87b51c39-1734-4d1a-bcd2-6fe706cdfc64",
            "conversationId": "a5ef47a2-0001",
            "groupId": "a5ef47a2-0001",
            "senderId": senderId,
            "senderName": senderName,
            "senderPhone": "+24390000000",
            "senderAvatar": "",
            "typeMessage": typeMessage,
            "isMessageSystem": true,
            "tenantId": "waangu-user",
            "country": "France",
            "content": content
        ]
    }

    private let alice: [String: Any] = [
        "userId": "645a3503ddb88a00085da11b", "username": "Alice",
        "phone": "+24390000000", "role": "OWNER"
    ]
    private let grace: [String: Any] = [
        "userId": "645a3503ddb88a00085da11d", "username": "GRACE_KABILA",
        "phone": "+24394444444", "role": "MEMBER"
    ]
    private let jakin: [String: Any] = [
        "userId": "110691817141112601", "username": "JAKIN IRISA",
        "phone": "098741201", "role": "MEMBER"
    ]

    /// Every event in the contract resolves, including the one that used to have
    /// no counterpart on this side at all.
    func test_resolvesEveryEventKind() {
        let kinds: [(String, MessageTypeProps)] = [
            ("GROUP_CREATED", .GROUP_CREATED),
            ("USER_ADDED_TO_GROUP", .USER_ADDED_TO_GROUP),
            ("USER_REMOVED_FROM_GROUP", .USER_REMOVED_FROM_GROUP),
            ("USER_LEFT_GROUP", .USER_LEFT_GROUP),
            ("USER_JOINED_GROUP", .USER_JOINED_GROUP),
            ("USER_PROMOTED_TO_ADMIN", .USER_PROMOTED_TO_ADMIN),
            ("USER_DEMOTED_FROM_ADMIN", .USER_DEMOTED_FROM_ADMIN),
            ("GROUP_UPDATED", .GROUP_UPDATED)
        ]
        for (raw, expected) in kinds {
            let dto = withoutParser(live(raw, targets: [grace]))
            XCTAssertEqual(dto?.resolvedGroupEvent?.type, expected, raw)
        }
    }

    /// The actor is the envelope's sender now — no digging through per-event keys.
    func test_actorIsTheEnvelopeSender() {
        let event = withoutParser(live(
            "USER_ADDED_TO_GROUP",
            text: "GRACE_KABILA has been added to the group \"Teyye\".",
            targets: [grace]
        ))?.resolvedGroupEvent

        XCTAssertEqual(event?.actorId, "645a3503ddb88a00085da11b")
        XCTAssertEqual(event?.actorName, "Alice")
        XCTAssertEqual(event?.primaryTarget?.userId, "645a3503ddb88a00085da11d")
        XCTAssertEqual(event?.primaryTarget?.displayName, "GRACE_KABILA")
    }

    /// Creation is the only event whose `targetUsers` is the whole group. Reading
    /// the others as a roster would leave a group with one member each time.
    func test_onlyCreationCarriesTheWholeRoster() {
        let created = withoutParser(live(
            "GROUP_CREATED",
            targets: [alice, grace, jakin],
            content: ["groupTitle": "Teyye"]
        ))?.resolvedGroupEvent
        XCTAssertEqual(created?.targets.count, 3)
        XCTAssertTrue(created?.carriesFullRoster ?? false)
        XCTAssertEqual(created?.title, "Teyye")

        let added = withoutParser(live("USER_ADDED_TO_GROUP", targets: [grace]))?.resolvedGroupEvent
        XCTAssertEqual(added?.targets.count, 1)
        XCTAssertFalse(added?.carriesFullRoster ?? true)
    }

    /// Leaving and joining name nobody but the person themselves, and the envelope
    /// sender is that person.
    func test_leaveAndJoinAreSelfPerformed() {
        for kind in ["USER_LEFT_GROUP", "USER_JOINED_GROUP"] {
            let event = withoutParser(live(
                kind,
                targets: [grace],
                senderId: "645a3503ddb88a00085da11d",
                senderName: "GRACE_KABILA"
            ))?.resolvedGroupEvent
            XCTAssertEqual(event?.actorId, "645a3503ddb88a00085da11d", kind)
            XCTAssertEqual(event?.actorName, "GRACE_KABILA", kind)
        }
    }

    /// The role events carry the member at their *new* role, which is what makes
    /// upserting them enough to keep admin badges honest.
    func test_roleEventsCarryTheNewRole() {
        let promoted = withoutParser(live(
            "USER_PROMOTED_TO_ADMIN",
            targets: [[
                "userId": "645a3503ddb88a00085da11d",
                "username": "GRACE_KABILA",
                "role": "ADMIN"
            ]]
        ))?.resolvedGroupEvent
        XCTAssertEqual(promoted?.primaryTarget?.participantRole, .admin)

        let demoted = withoutParser(live("USER_DEMOTED_FROM_ADMIN", targets: [grace]))?.resolvedGroupEvent
        XCTAssertEqual(demoted?.primaryTarget?.participantRole, .member)
    }

    /// An update is about the group, not about anyone in it.
    func test_updateCarriesMetadataAndNobody() {
        let event = withoutParser(live(
            "GROUP_UPDATED",
            text: "Alice updated group \"Teyye\".",
            content: [
                "groupTitle": "Teyye",
                "groupDescription": "New bio",
                "groupAvatar": "https://cdn/avatar.png",
                "groupAvatarUrl": "https://cdn/avatar.png",
                "groupIsLocked": false
            ]
        ))?.resolvedGroupEvent

        XCTAssertEqual(event?.type, .GROUP_UPDATED)
        XCTAssertTrue(event?.targets.isEmpty ?? false)
        XCTAssertEqual(event?.title, "Teyye")
        XCTAssertEqual(event?.avatar, "https://cdn/avatar.png")
    }

    /// End to end: stored, read back, and still the event it was.
    func test_liveShapeRoundTripsThroughStorage() {
        let crypto = PassthroughFieldCrypto()
        guard let dto = withoutParser(live("USER_JOINED_GROUP", targets: [grace])),
              let model = MessageModelMapper.toModel(from: dto, fieldCrypto: crypto)
        else { return XCTFail("expected a stored message") }

        XCTAssertEqual(model.type, .system)
        XCTAssertEqual(model.senderId, "645a3503ddb88a00085da11b")
        let item = MessageModelMapper.toDomain(model, fieldCrypto: crypto)
        XCTAssertEqual(item.typeMessage, .USER_JOINED_GROUP)
        XCTAssertEqual(item.message.groupEvent?.targetUserId, "645a3503ddb88a00085da11d")
    }

    /// The checkpoint each one becomes.
    func test_liveShapeBecomesTheRightCheckpoint() {
        let crypto = PassthroughFieldCrypto()
        let expected: [(String, ChatActionType)] = [
            ("USER_ADDED_TO_GROUP", .memberAdded),
            ("USER_JOINED_GROUP", .memberJoined),
            ("USER_LEFT_GROUP", .memberLeft),
            ("USER_REMOVED_FROM_GROUP", .memberRemoved),
            ("USER_PROMOTED_TO_ADMIN", .memberPromotedToAdmin),
            ("USER_DEMOTED_FROM_ADMIN", .memberDemotedFromAdmin),
            ("GROUP_UPDATED", .groupUpdated)
        ]
        for (raw, action) in expected {
            guard let dto = withoutParser(live(raw, targets: [grace])),
                  let model = MessageModelMapper.toModel(from: dto, fieldCrypto: crypto)
            else { return XCTFail("expected a stored message for \(raw)") }

            let item = MessageModelMapper.toDomain(model, fieldCrypto: crypto)
            let checkpoint = ChatActionItem(groupEvent: item, conversationId: "a5ef47a2-0001")
            XCTAssertEqual(checkpoint?.actionType, action, raw)
        }
    }

    /// Still not a real message, in the new shape either.
    func test_liveShapeNeverSpeaksForItsConversation() {
        guard let dto = withoutParser(live("USER_ADDED_TO_GROUP", targets: [grace])) else {
            return XCTFail("expected a decoded event")
        }
        XCTAssertFalse(ConversationPreviewPolicy.updatesPreview(dto))
    }

    // MARK: - GROUP_CREATED arriving as MESSAGE_SENT

    /// The whole live path in one test: MQTT delivers it as an ordinary
    /// `MESSAGE_SENT`, and it has to come out the other end as a group creation
    /// with its founding roster — not as a message.
    func test_groupCreatedInsideAMessageSentEnvelope() {
        let crypto = PassthroughFieldCrypto()
        guard let dto = decoded([
            "eventType": "MESSAGE_SENT",
            "payload": live(
                "GROUP_CREATED",
                text: "Alice created group \"Teyye\".",
                targets: [alice, grace, jakin],
                content: ["groupTitle": "Teyye"]
            )
        ]) else { return XCTFail("expected a decoded message") }

        guard let event = dto.resolvedGroupEvent else {
            return XCTFail("expected a group event, not a message")
        }
        XCTAssertEqual(event.type, .GROUP_CREATED)
        XCTAssertEqual(event.actorId, "645a3503ddb88a00085da11b")
        XCTAssertEqual(event.actorName, "Alice")
        XCTAssertEqual(event.title, "Teyye")
        XCTAssertEqual(event.targets.count, 3)
        XCTAssertTrue(event.carriesFullRoster)

        // Creation is about the group, not about a member — naming one would make
        // the owner the subject of "created the group".
        XCTAssertNil(event.primaryTarget)

        // The conversation it lands in must be a group, or the roster has nowhere
        // to go: `isGroupConversation` reads a non-empty groupId and no receiverId.
        XCTAssertEqual(dto.groupId, "a5ef47a2-0001")
        XCTAssertTrue((dto.receiverId ?? "").isEmpty)

        // And it must not speak for the conversation.
        XCTAssertFalse(ConversationPreviewPolicy.updatesPreview(dto))

        guard let model = MessageModelMapper.toModel(from: dto, fieldCrypto: crypto) else {
            return XCTFail("expected a stored message")
        }
        XCTAssertEqual(model.type, .system)
        XCTAssertEqual(model.senderId, "645a3503ddb88a00085da11b")
        XCTAssertEqual(
            MessageModelMapper.toDomain(model, fieldCrypto: crypto).typeMessage,
            .GROUP_CREATED
        )
    }

    /// Nothing in the payload says when it happened, so ingestion time is the only
    /// answer available. Fine live; wrong for anything replayed.
    func test_groupCreatedFallsBackToIngestionTimeWhenUndated() {
        guard let dto = withoutParser(live("GROUP_CREATED", targets: [alice])) else {
            return XCTFail("expected a decoded message")
        }
        XCTAssertEqual(dto.resolvedTimestamp, Date().timeIntervalSince1970, accuracy: 5)
    }

    // MARK: - The group has to actually show up

    /// The discussion list hides group conversations whose packed metadata does
    /// not say `synced` — a gate for groups this device is still creating. A group
    /// the backend told us about is synced by definition, and without saying so it
    /// is stored correctly and then filtered straight back out of the list.
    func test_syncedMetadataIsWhatMakesAGroupVisible() {
        XCTAssertFalse(
            GroupMapper.isSyncedMetadata(nil),
            "a conversation created by the sync delegate carries no metadata"
        )
        XCTAssertFalse(GroupMapper.isSyncedMetadata("pending|1|0|owner|#3B82F6"))
        XCTAssertTrue(GroupMapper.isSyncedMetadata(GroupMapper.syncedMetadata(createdBy: "owner-1")))
    }

    /// The creator has to survive into the packed metadata, because
    /// `isCurrentUserAdmin` short-circuits on it.
    func test_syncedMetadataKeepsTheCreator() {
        let packed = GroupMapper.syncedMetadata(createdBy: "owner-1")
        let group = GroupMapper.toDomain(
            ConversationModel(
                id: "local-1",
                serverId: "conv-9",
                type: .group,
                title: "Test one",
                assignedAgentName: packed
            ),
            members: []
        )
        XCTAssertEqual(group.createdBy, "owner-1")
        XCTAssertEqual(group.syncStatus, .synced)
        XCTAssertFalse(group.isPendingCreation)
        XCTAssertTrue(group.isActive, "a synced, non-pending group is what the list shows")
    }

    // MARK: - The group id is kept, not re-derived

    /// Outbound messages have a `groupId` field of their own and the group
    /// endpoints key on it, so it has to survive storage rather than be guessed
    /// back from the conversation id.
    func test_groupIdSurvivesStorage() {
        let crypto = PassthroughFieldCrypto()
        guard let dto = withoutParser(live("USER_ADDED_TO_GROUP", targets: [grace])),
              let model = MessageModelMapper.toModel(from: dto, fieldCrypto: crypto)
        else { return XCTFail("expected a stored message") }

        XCTAssertEqual(model.groupId, "a5ef47a2-0001")
        XCTAssertEqual(
            MessageModelMapper.toDomain(model, fieldCrypto: crypto).groupId,
            "a5ef47a2-0001"
        )
    }

    /// The group id must reach the group endpoints as its own value, and must not
    /// be written back into `serverId` on the way — persisting a fallback would
    /// erase the distinction on disk.
    func test_groupIdIsCarriedThroughTheGroupMapper() {
        let conversation = ConversationModel(
            id: "local-1",
            serverId: "conv-9",
            groupId: "group-9",
            type: .group,
            title: "Teyye"
        )
        let group = GroupMapper.toDomain(conversation, members: [])

        XCTAssertEqual(group.serverId, "conv-9")
        XCTAssertEqual(group.groupId, "group-9")
        XCTAssertEqual(group.resolvedGroupId, "group-9", "the group endpoints key on this")

        let roundTripped = GroupMapper.toConversation(group)
        XCTAssertEqual(roundTripped.serverId, "conv-9")
        XCTAssertEqual(roundTripped.groupId, "group-9", "must not collapse into serverId")
    }

    /// A group synced before the two ids were told apart has no stored group id,
    /// and the endpoints used the conversation id — the fallback keeps that exact
    /// behaviour rather than breaking those groups.
    func test_groupSyncedBeforeTheSplitStillResolves() {
        let legacy = GroupMapper.toDomain(
            ConversationModel(id: "local-1", serverId: "conv-9", type: .group, title: "Teyye"),
            members: []
        )
        XCTAssertNil(legacy.groupId)
        XCTAssertEqual(legacy.resolvedGroupId, "conv-9")
    }

    /// Rows written before the field existed have no group id, and every call site
    /// used the conversation id anyway — so the fallback has to keep behaving
    /// exactly as they did.
    func test_groupIdFallsBackForRowsThatPredateIt() {
        let migrated = ConversationModel(
            id: "conv-1",
            serverId: "conv-1",
            type: .group,
            title: "Teyye"
        )
        XCTAssertEqual(migrated.resolvedGroupId, "conv-1")

        let stored = ConversationModel(
            id: "conv-1",
            serverId: "conv-1",
            groupId: "group-9",
            type: .group,
            title: "Teyye"
        )
        XCTAssertEqual(stored.resolvedGroupId, "group-9", "the stored id wins once present")
    }

    // MARK: - The previous shape, still on the wire mid-rollout

    /// Before the kind moved onto `typeMessage`, it lived in `content.eventType`,
    /// the envelope was sent by the literal `"system"`, and the actor was named by
    /// a different key per event. A device that syncs across the rollout sees both,
    /// so both still have to resolve.
    func test_stillReadsThePreviousShape() {
        let event = decoded(wrapped(
            eventType: "GROUP_CREATED",
            content: [
                "text": "JAKIN IRISA created group \"tes\".",
                "createdBy": [
                    "userId": "userC",
                    "username": "JAKIN IRISA",
                    "phone": "098741201",
                    "role": "OWNER"
                ]
            ]
        ))?.resolvedGroupEvent

        XCTAssertEqual(event?.type, .GROUP_CREATED)
        XCTAssertEqual(event?.actorId, "userC", "the envelope says \"system\"; the actor is in the content")
        XCTAssertEqual(event?.actorName, "JAKIN IRISA")
        XCTAssertEqual(event?.title, "tes")
        XCTAssertEqual(event?.targets.count, 2, "the roster used to be called participants")
    }

    /// The flat form has no message envelope at all and still needs one built.
    func test_stillWrapsTheFlatForm() {
        let event = decoded([
            "eventType": "USER_REMOVED_FROM_GROUP",
            "conversationId": "conv-1",
            "removedBy": "userA",
            "targetUserId": "userC",
            "title": "Famille",
            "participants": participants
        ])?.resolvedGroupEvent

        XCTAssertEqual(event?.type, .USER_REMOVED_FROM_GROUP)
        XCTAssertEqual(event?.actorId, "userA")
        XCTAssertEqual(event?.title, "Famille")
    }

    /// An ordinary message on the same envelope must be untouched.
    func test_ordinaryMessageIsNotAGroupEvent() {
        let dto = withoutParser([
            "codeMessage": "m1",
            "senderId": "userA",
            "senderName": "Aline",
            "conversationId": "conv-1",
            "content": "{\"text\":\"hello\"}",
            "typeMessage": "TEXT"
        ])
        XCTAssertNil(dto?.resolvedGroupEvent)
        XCTAssertTrue(ConversationPreviewPolicy.updatesPreview(dto!))
    }
}

/// Storage encrypts display names and message text on the way in and decrypts them
/// on the way out. These tests are about what survives the round trip, not about
/// the cipher, so both directions are the identity.
private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
