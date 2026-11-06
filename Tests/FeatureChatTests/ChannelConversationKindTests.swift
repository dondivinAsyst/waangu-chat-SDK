//
//  ChannelConversationKindTests.swift
//  FeatureChatTests
//
//  The bug class that hid channel messages: a broadcast written as a group.
//

import XCTest
@testable import WaanguFeatureChat

final class ChannelConversationKindTests: XCTestCase {

    // MARK: - The kind itself

    /// A broadcast travels as a group on the wire — it is fanned out, not
    /// delivered to one person — which is exactly why the kind has to survive
    /// alongside that fact instead of collapsing into it.
    func test_channelTravelsAsGroupButIsNotOne() {
        XCTAssertTrue(ConversationKind.channel.travelsAsGroup)
        XCTAssertTrue(ConversationKind.group.travelsAsGroup)
        XCTAssertFalse(ConversationKind.direct.travelsAsGroup)

        XCTAssertNotEqual(ConversationKind.channel, .group)
    }

    func test_onlyDirectHasASinglePeer() {
        XCTAssertFalse(ConversationKind.direct.isMultiParty)
        XCTAssertTrue(ConversationKind.group.isMultiParty)
        XCTAssertTrue(ConversationKind.channel.isMultiParty)
    }

    // MARK: - The kind reaching the stored row

    /// The regression that cost a day: sending into a channel built a contact
    /// row that said "group", and the store believed it.
    func test_contactChannelCarriesTheKind() {
        let channel = DiscussionContactBuilder.contactChannel(from: nil, kind: .channel)
        XCTAssertTrue(channel.isChannel)
        XCTAssertTrue(channel.isGroup, "a broadcast still travels as a group")

        let group = DiscussionContactBuilder.contactChannel(from: nil, kind: .group)
        XCTAssertFalse(group.isChannel)
        XCTAssertTrue(group.isGroup)

        let direct = DiscussionContactBuilder.contactChannel(from: nil, kind: .direct)
        XCTAssertFalse(direct.isChannel)
        XCTAssertFalse(direct.isGroup)
    }

    /// `isChannel` has to win over `isGroup` when the row is written, or the
    /// conversation comes back as a group and both lists reject it.
    func test_mapperStoresAChannelAsAChannel() {
        let mapper = DiscussionMapper()

        let stored = mapper.toGRDB(discussion(isGroup: true, isChannel: true))
        XCTAssertEqual(stored.type, .channel)

        XCTAssertEqual(mapper.toGRDB(discussion(isGroup: true, isChannel: false)).type, .group)
        XCTAssertEqual(mapper.toGRDB(discussion(isGroup: false, isChannel: false)).type, .direct)
    }

    /// And back out again: a stored channel must still read as a channel, or the
    /// chats list stops filtering it and the Updates list stops finding it.
    func test_mapperReadsAChannelBackAsOne() {
        let mapper = DiscussionMapper()
        let stored = mapper.toGRDB(discussion(isGroup: true, isChannel: true))

        let item = mapper.toDomain(stored)
        XCTAssertEqual(item.contact?.isChannel, true)
        XCTAssertEqual(item.contact?.isGroup, true)
    }

    /// The chats list drops channels; Updates keeps them. One predicate, two
    /// lists, and it is the only thing standing between a broadcast and the
    /// wrong tab.
    func test_chatsListExcludesChannelsOnly() {
        let mapper = DiscussionMapper()
        let rows = [
            mapper.toDomain(mapper.toGRDB(discussion(isGroup: true, isChannel: true))),
            mapper.toDomain(mapper.toGRDB(discussion(isGroup: true, isChannel: false))),
            mapper.toDomain(mapper.toGRDB(discussion(isGroup: false, isChannel: false)))
        ]

        let chats = rows.filter { $0.contact?.isChannel != true }
        XCTAssertEqual(chats.count, 2)
        XCTAssertTrue(chats.allSatisfy { $0.contact?.isChannel != true })
    }

    // MARK: - Helpers

    private func discussion(isGroup: Bool, isChannel: Bool) -> DiscussionChatItem {
        DiscussionChatItem(
            lastMessage: MessageDataItem(
                codeMessage: "m1",
                senderId: "u1",
                groupId: "c1",
                typeMessage: .TEXT,
                message: MessageContent(text: "hello"),
                status: .SENT,
                createdAt: Date(timeIntervalSince1970: 1_770_000_000)
            ),
            conversationId: "c1",
            contact: ContactChannel(
                userName: "Actu Waangu",
                phone: "",
                image: nil,
                isBlocked: false,
                isGroup: isGroup,
                isChannel: isChannel,
                id: "c1"
            )
        )
    }
}

// MARK: - Follower counts

/// The count stayed at zero because Identity spells it more than one way and we
/// read exactly one of them. A key we do not read decodes as nil.
final class ChannelFollowerCountTests: XCTestCase {

    func test_everySpellingOfTheCountIsRead() throws {
        for key in ["subscriberCount", "subscribersCount", "followerCount", "followersCount", "totalSubscribers"] {
            let json = #"{"id":"c1","channelName":"Actu","\#(key)":42}"#
            let dto = try JSONDecoder().decode(ChannelDto.self, from: Data(json.utf8))
            XCTAssertEqual(dto.subscriberCount, 42, "\(key) was not read")
        }
    }

    func test_everySpellingOfFollowingIsRead() throws {
        for key in ["isSubscribed", "subscribed", "following"] {
            let json = #"{"id":"c1","channelName":"Actu","\#(key)":true}"#
            let dto = try JSONDecoder().decode(ChannelDto.self, from: Data(json.utf8))
            XCTAssertEqual(dto.isSubscribed, true, "\(key) was not read")
        }
    }

    /// A channel with no count at all is zero followers, not a decode failure.
    func test_missingCountDecodesAsNil() throws {
        let json = #"{"id":"c1","channelName":"Actu"}"#
        let dto = try JSONDecoder().decode(ChannelDto.self, from: Data(json.utf8))
        XCTAssertNil(dto.subscriberCount)
        XCTAssertEqual(ChannelMapper.toDomain(dto).subscriberCount, 0)
    }
}
