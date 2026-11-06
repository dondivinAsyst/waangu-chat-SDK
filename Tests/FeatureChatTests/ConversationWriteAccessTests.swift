//
//  ConversationWriteAccessTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 3.4 — un canal de diffusion n'offre aucune action de conversation à qui ne peut
//  pas y publier, et les groupes d'annonces d'une communauté sont réservés à leurs administrateurs.
//
//  Le résolveur n'avait aucun test. Il décide si le compositeur est proposé ; ce n'est jamais la
//  seule barrière (le serveur refuse aussi l'envoi), il évite de proposer une action refusée.
//

import XCTest
@testable import WaanguFeatureChat

final class ConversationWriteAccessTests: XCTestCase {

    private func resolver(
        channels: StubChannels = StubChannels(),
        communities: StubCommunities = StubCommunities(),
        me: String = "me"
    ) -> ConversationWriteAccessResolver {
        ConversationWriteAccessResolver(channelRepository: channels,
                                        communityRepository: communities,
                                        currentUserId: { me })
    }

    private func channel(owner: String, conversation: String? = "conv-1") -> Channel {
        Channel(id: "ch-1", name: "Actu", conversationId: conversation, createdByUserId: owner)
    }

    // MARK: Canaux

    func test_theChannelsOwner_mayPost() async {
        let r = resolver(channels: StubChannels(result: .found(channel(owner: "me"))))

        let restriction = await r.restriction(forConversationId: "conv-1")

        XCTAssertNil(restriction)
    }

    func test_aFollower_getsNoComposer() async {
        let r = resolver(channels: StubChannels(result: .found(channel(owner: "someone-else"))))

        let restriction = await r.restriction(forConversationId: "conv-1")

        XCTAssertEqual(restriction, .channelOwnerOnly)
    }

    /// Les identifiants se comparent sans tenir compte de la casse.
    func test_theOwnerIdIsComparedWithoutCase() async {
        let r = resolver(channels: StubChannels(result: .found(channel(owner: "ME"))), me: "me")

        let restriction = await r.restriction(forConversationId: "conv-1")

        XCTAssertNil(restriction)
    }

    /// Constat 2026-11-06 : seul le créateur publie. `ChannelAdmin` est documenté comme « quelqu'un
    /// d'autre qui peut publier », mais Identity n'expose pas encore les administrateurs de canal
    /// (la route est servie en mémoire en DEBUG), donc la règle actuelle suit ce que le serveur sait faire.
    func test_aChannelAdmin_isNotAPosterYet() async {
        let stub = StubChannels(result: .found(channel(owner: "creator")))

        let restriction = await resolver(channels: stub, me: "an-admin").restriction(forConversationId: "conv-1")

        XCTAssertEqual(restriction, .channelOwnerOnly)
    }

    func test_aChannelWithoutAConversation_isNeverOpenToPost() async {
        let r = resolver(channels: StubChannels(result: .found(channel(owner: "me", conversation: nil))))

        let restriction = await r.restriction(forConversationId: "conv-1")

        XCTAssertEqual(restriction, .channelOwnerOnly)
    }

    // MARK: Communautés

    private func context(announcement: Bool, role: CommunityRole?) -> (community: Community, group: CommunityGroupSummary) {
        (Community(id: "c1", name: "C", myRole: role),
         CommunityGroupSummary(id: "g1", name: "G", isAnnouncementGroup: announcement, conversationId: "conv-2"))
    }

    func test_announcements_areForAdminsOnly() async {
        for role in [CommunityRole.owner, .admin] {
            let r = resolver(communities: StubCommunities(result: .found(context(announcement: true, role: role))))
            let restriction = await r.restriction(forConversationId: "conv-2")
            XCTAssertNil(restriction, "\(role)")
        }
        for role in [CommunityRole.moderator, .member] {
            let r = resolver(communities: StubCommunities(result: .found(context(announcement: true, role: role))))
            let restriction = await r.restriction(forConversationId: "conv-2")
            XCTAssertEqual(restriction, .announcementsAdminsOnly, "\(role)")
        }
    }

    func test_anOrdinarySubGroup_isOpenToItsMembers() async {
        let r = resolver(communities: StubCommunities(result: .found(context(announcement: false, role: .member))))

        let restriction = await r.restriction(forConversationId: "conv-2")

        XCTAssertNil(restriction)
    }

    // MARK: Cas limites

    /// Un canal l'emporte sur une communauté pour la même conversation.
    func test_aChannel_winsOverACommunityForTheSameConversation() async {
        let r = resolver(channels: StubChannels(result: .found(channel(owner: "someone-else"))),
                         communities: StubCommunities(result: .found(context(announcement: false, role: .member))))

        let restriction = await r.restriction(forConversationId: "conv-1")

        XCTAssertEqual(restriction, .channelOwnerOnly)
    }

    func test_aPlainGroupOrDirectChat_isNeverRestricted() async {
        let restriction = await resolver().restriction(forConversationId: "conv-9")

        XCTAssertNil(restriction)
    }

    func test_anEmptyConversationId_isNeverRestricted() async {
        let r = resolver(channels: StubChannels(result: .found(channel(owner: "someone-else"))))

        let restriction = await r.restriction(forConversationId: "")

        XCTAssertNil(restriction)
    }

    /// Choix de conception documenté : si la réponse échoue, on ne verrouille pas une conversation
    /// ordinaire. Le serveur refuserait de toute façon l'envoi.
    func test_aLookupThatFails_leavesTheRoomUnrestricted() async {
        let r = resolver(channels: StubChannels(result: .fails), communities: StubCommunities(result: .fails))

        let restriction = await r.restriction(forConversationId: "conv-1")

        XCTAssertNil(restriction)
    }
}

// MARK: - Doublures (seules deux fonctions servent ; les autres échouent si on les appelle)

private struct NotUsed: Error {}

private enum Answer<T> { case none, found(T), fails }

private struct StubChannels: ChannelRepositoryProtocol {
    var result: Answer<Channel> = .none

    func channel(forConversationId conversationId: String) async throws -> Channel? {
        switch result {
        case .none: return nil
        case .found(let channel): return channel
        case .fails: throw NotUsed()
        }
    }

    func channels(page: Int, size: Int) async throws -> [Channel] { throw NotUsed() }
    func subscribedChannels() async throws -> [Channel] { throw NotUsed() }
    func channel(id: String) async throws -> Channel { throw NotUsed() }
    func create(_ draft: NewChannelDraft) async throws -> Channel { throw NotUsed() }
    func update(channelId: String, name: String?, type: ChannelType?, image: String?,
                description: String?) async throws -> Channel { throw NotUsed() }
    func admins(channelId: String) async throws -> [ChannelAdmin] { throw NotUsed() }
    func addAdmin(channelId: String, userId: String, userName: String) async throws { throw NotUsed() }
    func removeAdmin(channelId: String, userId: String) async throws { throw NotUsed() }
    func subscribe(channelId: String) async throws -> ChannelSubscriptionOutcome { throw NotUsed() }
    func unsubscribe(channelId: String) async throws -> ChannelSubscriptionOutcome { throw NotUsed() }
    func generateInviteLink(channelId: String, expiresIn: Int?, maxUses: Int?) async throws -> ChannelInviteLink { throw NotUsed() }
    func getInviteLink(channelId: String) async throws -> ChannelInviteLink { throw NotUsed() }
    func revokeInviteLink(channelId: String) async throws { throw NotUsed() }
    func joinByCode(inviteCode: String) async throws -> (channel: Channel, wasAlreadySubscribed: Bool) { throw NotUsed() }
}

private struct StubCommunities: CommunityRepositoryProtocol {
    var result: Answer<(community: Community, group: CommunityGroupSummary)> = .none

    func groupContext(forConversationId conversationId: String) async throws -> (community: Community, group: CommunityGroupSummary)? {
        switch result {
        case .none: return nil
        case .found(let context): return context
        case .fails: throw NotUsed()
        }
    }

    func myCommunities(refresh: Bool) async throws -> [Community] { throw NotUsed() }
    func discoverCommunities(page: Int, size: Int) async throws -> [Community] { throw NotUsed() }
    func community(id: String) async throws -> Community { throw NotUsed() }
    func create(_ draft: NewCommunityDraft) async throws -> Community { throw NotUsed() }
    func update(communityId: String, name: String?, description: String?, image: String?) async throws -> Community { throw NotUsed() }
    func delete(communityId: String) async throws { throw NotUsed() }
    func join(communityId: String) async throws -> CommunityMembershipOutcome { throw NotUsed() }
    func join(inviteCode: String) async throws -> CommunityMembershipOutcome { throw NotUsed() }
    func leave(communityId: String) async throws -> CommunityMembershipOutcome { throw NotUsed() }
    func addMember(communityId: String, userId: String, userName: String) async throws { throw NotUsed() }
    func removeMember(communityId: String, userId: String) async throws { throw NotUsed() }
    func updateRole(communityId: String, userId: String, role: CommunityRole) async throws { throw NotUsed() }
    func transferOwnership(communityId: String, newOwnerUserId: String) async throws { throw NotUsed() }
    func groups(communityId: String) async throws -> [CommunityGroupSummary] { throw NotUsed() }
    func groupMembers(communityId: String, groupId: String) async throws -> [CommunityMember] { throw NotUsed() }
    func settings(communityId: String) async throws -> CommunitySettings { throw NotUsed() }
    func updateSettings(communityId: String, settings: CommunitySettings) async throws { throw NotUsed() }
    func joinGroup(communityId: String, groupId: String) async throws { throw NotUsed() }
    func linkGroup(communityId: String, groupId: String) async throws { throw NotUsed() }
    func unlinkGroup(communityId: String, groupId: String) async throws { throw NotUsed() }
}
