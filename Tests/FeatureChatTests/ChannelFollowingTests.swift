//
//  ChannelFollowingTests.swift
//  FeatureChatTests
//
//  Who follows a channel — Identity's subscriber list first, the inbox as fallback.
//

import XCTest
@testable import WaanguFeatureChat

final class ChannelFollowingTests: XCTestCase {

    private let me = "100000000000000001"

    // MARK: - Decoding

    /// The listing entry exactly as Identity sent it after a Follow.
    func test_listingDecodesTheSubscriberIds() throws {
        let channel = try decodeListing(Self.listingJSON)
        XCTAssertEqual(channel.subscriberIds, ["645a3503ddb88a00085da11b", me])
        XCTAssertEqual(channel.subscriberCount, 2)
    }

    func test_bannedSubscriber_doesNotFollow() throws {
        let json = Self.listingJSON.replacingOccurrences(
            of: #""userId":"645a3503ddb88a00085da11b","subscribedAt":"2026-09-14T15:59:07.449977Z","banned":false"#,
            with: #""userId":"645a3503ddb88a00085da11b","subscribedAt":"2026-09-14T15:59:07.449977Z","banned":true"#)
        XCTAssertEqual(try decodeListing(json).subscriberIds, [me])
    }

    /// `byId` omits the list: that is no answer, not "nobody follows".
    func test_missingSubscriberList_isNil_notEmpty() throws {
        let json = #"{"message":"Canal trouvé","status":200,"data":{"id":"c1","channelName":"ttest 02","conversationId":"conv_1","createdByUserId":"owner"}}"#
        let response = try JSONDecoder().decode(ChannelAPIResponse.self, from: Data(json.utf8))
        XCTAssertNil(ChannelMapper.toDomain(try XCTUnwrap(response.data)).subscriberIds)
    }

    func test_emptySubscriberList_isAnAnswer() throws {
        let json = #"{"status":200,"data":[{"id":"c1","channelName":"Ouf Channel","subscribers":[],"subscriberCount":0}]}"#
        XCTAssertEqual(try decodeListing(json).subscriberIds, [])
    }

    /// A list in an unexpected shape costs the list, never the channel.
    func test_malformedSubscriberList_keepsTheChannel() throws {
        let json = #"{"status":200,"data":[{"id":"c1","channelName":"x","subscribers":"everyone"}]}"#
        let channel = try decodeListing(json)
        XCTAssertEqual(channel.id, "c1")
        XCTAssertNil(channel.subscriberIds)
    }

    // MARK: - Decision

    /// The bug: Follow succeeded, the inbox had not synced yet, the button stayed "Follow".
    func test_followedRightAfterSubscribing_evenBeforeTheInboxSyncs() throws {
        let channel = try decodeListing(Self.listingJSON)
        XCTAssertTrue(ChannelFollowing.isFollowed(channel, currentUserId: me, inboxConversationIds: []))
    }

    /// The mirror bug: after Unfollow the conversation is still stored locally.
    func test_unfollowed_evenWhileTheConversationIsStillStored() {
        let channel = Channel(id: "c1", name: "ttest 02", conversationId: "conv_1",
                              createdByUserId: "owner", subscriberIds: ["someone-else"])
        XCTAssertFalse(ChannelFollowing.isFollowed(channel, currentUserId: me, inboxConversationIds: ["conv_1"]))
    }

    func test_withoutAList_theInboxDecides() {
        let channel = Channel(id: "c1", name: "x", conversationId: "conv_1", createdByUserId: "owner")
        XCTAssertTrue(ChannelFollowing.isFollowed(channel, currentUserId: me, inboxConversationIds: ["conv_1"]))
        XCTAssertFalse(ChannelFollowing.isFollowed(channel, currentUserId: me, inboxConversationIds: []))
    }

    func test_creatorFollows_whateverTheListSays() {
        let channel = Channel(id: "c1", name: "x", createdByUserId: me, subscriberIds: [])
        XCTAssertTrue(ChannelFollowing.isFollowed(channel, currentUserId: me, inboxConversationIds: []))
    }

    /// No session user: nothing matches, rather than an empty id matching an empty entry.
    func test_noCurrentUser_followsNothingFromTheList() {
        let channel = Channel(id: "c1", name: "x", createdByUserId: "owner", subscriberIds: [""])
        XCTAssertFalse(ChannelFollowing.isFollowed(channel, currentUserId: "", inboxConversationIds: []))
    }

    // MARK: - Fixtures

    private func decodeListing(_ json: String) throws -> Channel {
        let response = try JSONDecoder().decode(ChannelListAPIResponse.self, from: Data(json.utf8))
        return ChannelMapper.toDomain(try XCTUnwrap(response.data?.first))
    }

    private static let listingJSON = #"""
    {"message":"Canaux","status":200,"data":[{"id":"ab432ab6-866a-4c6f-84a2-6db855b7cceb","tenantId":"waangu-user","channelName":"ttest 02","channelType":"TEXT","image":"http://192.168.30.43:9000/waangu-chat-media/default/message/WAANGU_1788268370691.jpg","deleted":false,"createdAt":"2026-09-01T13:13:03.368258Z","updatedAt":"2026-09-01T13:13:03.368258Z","subscribers":[{"userId":"645a3503ddb88a00085da11b","subscribedAt":"2026-09-14T15:59:07.449977Z","banned":false,"bannedAt":null,"bannedReason":null,"bannedBy":null},{"userId":"100000000000000001","subscribedAt":"2026-09-16T14:50:12.620976Z","banned":false,"bannedAt":null,"bannedReason":null,"bannedBy":null}],"subscriberCount":2,"createdByUserId":"110691817141112601","conversationId":"7806ec73-b989-4b19-a12f-aa3d962c631c"}]}
    """#
}
