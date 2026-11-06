import XCTest
import WaanguNetworkKit
@testable import WaanguFeatureChat

/// The pieces of the communities & channels integration that can be checked
/// without a server: the endpoint contract, the DTO → entity mapping, the error
/// names Identity reports, and the conversation type that used to be dropped.
final class CommunityChannelIntegrationTests: XCTestCase {

    // MARK: - Conversation type

    func test_broadcastConversationIsAChannel() {
        // The bug this guards: BROADCAST fell into the default branch, became
        // `.direct`, found no peer, and the inbox dropped every subscribed
        // channel.
        XCTAssertEqual(ConversationTypeMapper.model(from: "BROADCAST"), .channel)
        XCTAssertEqual(ConversationTypeMapper.model(from: "broadcast"), .channel)
        XCTAssertEqual(ConversationTypeMapper.model(from: "GROUP"), .group)
        XCTAssertEqual(ConversationTypeMapper.model(from: "DIRECT"), .direct)
    }

    func test_onlyDirectConversationsCarryAPeer() {
        XCTAssertTrue(ConversationTypeMapper.isDirect("DIRECT"))
        XCTAssertFalse(ConversationTypeMapper.isDirect("BROADCAST"))
        XCTAssertFalse(ConversationTypeMapper.isDirect("GROUP"))
    }

    func test_unknownTypeStaysDirect() {
        // A type this app has not been taught yet must not vanish from the inbox.
        XCTAssertEqual(ConversationTypeMapper.model(from: "SOMETHING_NEW"), .direct)
    }

    func test_groupAndChannelAreBothMultiParty() {
        XCTAssertTrue(ConversationTypeModel.group.isMultiParty)
        XCTAssertTrue(ConversationTypeModel.channel.isMultiParty)
        XCTAssertFalse(ConversationTypeModel.direct.isMultiParty)
    }

    // MARK: - Endpoints

    func test_communityEndpointPaths() {
        XCTAssertEqual(CommunityEndpoints.mine(page: 0, size: 20).path, "/identity/communities/me")
        XCTAssertEqual(CommunityEndpoints.delete(CommunityIdRequest(communityId: "c1")).path,
                       "/identity/communities/delete")
        XCTAssertEqual(CommunityEndpoints.membership(.joining(communityId: "c1")).path,
                       "/identity/communities/membership")
        XCTAssertEqual(CommunityEndpoints.updateMemberRole(
            UpdateCommunityMemberRoleRequest(communityId: "c1", userId: "u1", role: "ADMIN")
        ).path, "/identity/communities/members/role")
        XCTAssertEqual(CommunityEndpoints.transferOwner(
            TransferCommunityOwnerRequest(communityId: "c1", newOwnerUserId: "u2")
        ).path, "/identity/communities/owner/transfer")
        XCTAssertEqual(CommunityEndpoints.groupMembers(communityId: "c1", groupId: "g1").path,
                       "/identity/communities/groups/members")
    }

    func test_channelEndpointPaths() {
        XCTAssertEqual(ChannelEndpoints.list(page: 0, size: 50).path, "/identity/channels")
        XCTAssertEqual(ChannelEndpoints.byId(channelId: "ch1").path, "/identity/channels/byId")
        XCTAssertEqual(ChannelEndpoints.subscription(.subscribing(to: "ch1")).path,
                       "/identity/channels/subscription")
    }

    func test_readsAreIdempotentAndWritesAreNot() {
        XCTAssertTrue(CommunityEndpoints.list(page: 0, size: 20).isIdempotent)
        XCTAssertFalse(CommunityEndpoints.membership(.leaving(communityId: "c1")).isIdempotent)
        XCTAssertTrue(ChannelEndpoints.byId(channelId: "ch1").isIdempotent)
        XCTAssertFalse(ChannelEndpoints.subscription(.subscribing(to: "ch1")).isIdempotent)
    }

    func test_membershipBodyCarriesTheRightMove() throws {
        let join = try XCTUnwrap(CommunityEndpoints.membership(.joining(communityId: "c1")).parameters)
        XCTAssertEqual(join["leave"] as? Bool, false)
        XCTAssertEqual(join["communityId"] as? String, "c1")

        let byCode = try XCTUnwrap(CommunityEndpoints.membership(.joining(inviteCode: "ABC12XYZ")).parameters)
        XCTAssertEqual(byCode["inviteCode"] as? String, "ABC12XYZ")
        XCTAssertNil(byCode["communityId"])

        let leave = try XCTUnwrap(CommunityEndpoints.membership(.leaving(communityId: "c1")).parameters)
        XCTAssertEqual(leave["leave"] as? Bool, true)
    }

    func test_subscriptionBodyFlipsWithTheVerb() throws {
        let on = try XCTUnwrap(ChannelEndpoints.subscription(.subscribing(to: "ch1")).parameters)
        XCTAssertEqual(on["subscribe"] as? Bool, true)

        let off = try XCTUnwrap(ChannelEndpoints.subscription(.unsubscribing(from: "ch1")).parameters)
        XCTAssertEqual(off["subscribe"] as? Bool, false)
    }

    // MARK: - Decoding

    func test_communityDecodesWithAnnouncementsFirst() throws {
        let json = """
        {
          "statusCode": 200,
          "message": "OK",
          "data": {
            "id": "c1",
            "name": "Tech Enthusiasts",
            "isPrivate": false,
            "inviteCode": "ABC12XYZ",
            "announcementGroupId": "g-ann",
            "memberCount": 3,
            "myRole": "ADMIN",
            "groups": [
              { "id": "g-chat", "name": "Général", "isAnnouncementGroup": false,
                "conversationId": "conv-chat", "memberCount": 2 },
              { "id": "g-ann", "name": "Annonces Tech", "isAnnouncementGroup": true,
                "conversationId": "conv-ann", "memberCount": 3,
                "members": [ { "userId": "u1", "userName": "Marie", "role": "OWNER" } ] }
            ],
            "createdAt": "2026-08-28T10:15:30.123Z"
          },
          "metadata": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CommunityAPIResponse.self, from: json)
        let community = CommunityMapper.toDomain(try XCTUnwrap(response.data))

        XCTAssertEqual(community.name, "Tech Enthusiasts")
        XCTAssertEqual(community.myRole, .admin)
        XCTAssertEqual(community.maxMembers, Community.defaultMaxMembers)
        // Announcements leads, whatever order the server sent.
        XCTAssertEqual(community.groups.first?.id, "g-ann")
        XCTAssertEqual(community.announcementGroup?.conversationId, "conv-ann")
        XCTAssertEqual(community.chatGroups.map(\.id), ["g-chat"])
        XCTAssertEqual(community.announcementGroup?.members.first?.userName, "Marie")
        // Fractional seconds: the shared decoder's strict .iso8601 rejects these,
        // which is why timestamps are read as strings and parsed in the mapper.
        XCTAssertNotNil(community.createdAt)
    }

    func test_channelWithoutConversationCannotBeOpened() throws {
        let json = """
        { "statusCode": 200, "message": "OK",
          "data": { "id": "ch1", "channelName": "Actu Waangu", "channelType": "TEXT",
                    "createdByUserId": "u1", "subscriberCount": 12 } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ChannelAPIResponse.self, from: json)
        let channel = ChannelMapper.toDomain(try XCTUnwrap(response.data))

        XCTAssertEqual(channel.name, "Actu Waangu")
        XCTAssertEqual(channel.type, .text)
        // Created before Identity's V12 migration: listed, but nothing to open.
        XCTAssertFalse(channel.isOpenable)
        XCTAssertFalse(channel.canPost(as: "u1"))
    }

    func test_channelOwnerIsTheOnlyPoster() {
        let channel = Channel(
            id: "ch1",
            name: "Actu",
            conversationId: "conv-1",
            createdByUserId: "u1"
        )
        XCTAssertTrue(channel.canPost(as: "u1"))
        XCTAssertTrue(channel.canPost(as: "U1"), "Ids compare case-insensitively")
        XCTAssertFalse(channel.canPost(as: "u2"))
        XCTAssertFalse(channel.canPost(as: ""))
    }

    // MARK: - Write rules

    func test_announcementsAreAdminOnlyAndSubGroupsAreNot() {
        let announcements = CommunityGroupSummary(id: "g1", name: "Annonces", isAnnouncementGroup: true)
        XCTAssertTrue(announcements.canWrite(as: .owner))
        XCTAssertTrue(announcements.canWrite(as: .admin))
        XCTAssertFalse(announcements.canWrite(as: .moderator))
        XCTAssertFalse(announcements.canWrite(as: .member))
        XCTAssertFalse(announcements.canWrite(as: nil))

        let subGroup = CommunityGroupSummary(id: "g2", name: "Général")
        XCTAssertTrue(subGroup.canWrite(as: .member))
    }

    // MARK: - Errors

    func test_identityErrorNamesBecomeDomainErrors() {
        func mapped(_ message: String) -> CommunityError {
            CommunityErrorMapper.map(APIError.clientError(statusCode: 409, message: message))
        }

        XCTAssertEqual(mapped("ALREADY_MEMBER"), .alreadyMember)
        XCTAssertEqual(mapped("PRIVATE_COMMUNITY"), .privateCommunityRequiresInviteCode)
        XCTAssertEqual(mapped("COMMUNITY_FULL"), .full(maxMembers: Community.defaultMaxMembers))
        XCTAssertEqual(mapped("CANNOT_DETACH_ANNOUNCEMENTS"), .cannotDetachAnnouncements)
        XCTAssertEqual(mapped("GROUP_NOT_IN_COMMUNITY"), .groupNotInCommunity)
        // A sentence containing the code counts too.
        XCTAssertEqual(mapped("User is ALREADY_MEMBER of this community"), .alreadyMember)
    }

    func test_channelErrorNames() {
        XCTAssertEqual(
            ChannelErrorMapper.map(APIError.clientError(statusCode: 409, message: "CHANNEL_BANNED")),
            .banned
        )
        XCTAssertEqual(
            ChannelErrorMapper.map(APIError.clientError(statusCode: 409, message: "CHANNEL_TENANT_MISMATCH")),
            .tenantMismatch
        )
        // 403 arrives with no body. On a subscribe it can only be a ban; on any
        // other call it stays a plain refusal rather than a guess.
        XCTAssertEqual(ChannelErrorMapper.map(APIError.forbidden, subscribing: true), .banned)
        XCTAssertEqual(ChannelErrorMapper.map(APIError.forbidden), .forbidden)
    }

    // MARK: - Timestamps

    func test_timestampsParseWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(ISO8601Timestamp.date(from: "2026-08-28T10:15:30.123Z"))
        XCTAssertNotNil(ISO8601Timestamp.date(from: "2026-08-28T10:15:30Z"))
        XCTAssertNil(ISO8601Timestamp.date(from: ""))
        XCTAssertNil(ISO8601Timestamp.date(from: nil))
        XCTAssertNil(ISO8601Timestamp.date(from: "not a date"))
    }
}
