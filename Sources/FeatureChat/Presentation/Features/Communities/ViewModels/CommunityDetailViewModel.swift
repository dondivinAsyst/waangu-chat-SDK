//
//  CommunityDetailViewModel.swift
//  FeatureChat
//

import Foundation
import Combine
import UIKit
import WaanguCoreKit

/// One community: its groups, its members, and what this user may do in it.
@available(iOS 16.0, *)
@MainActor
public final class CommunityDetailViewModel: ObservableObject {

    @Published private(set) var community: Community?
    @Published private(set) var groups: [CommunityGroupSummary] = []
    /// Conversation activity per group, keyed by conversation id.
    @Published private(set) var previews: [String: ConversationPreview] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// Set when the user has left or deleted the community and the screen has
    /// nothing left to show.
    @Published private(set) var didLeave = false
    /// Groups this user could attach: their own, already synced, and not in the
    /// community yet.
    @Published private(set) var linkableGroups: [GroupChat] = []

    let communityId: String
    private let useCases: CommunityUseCasesProtocol
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let groupUseCases: GroupUseCasesProtocol
    /// Parks an avatar in media storage and hands back its URL.
    private let uploadAvatar: UploadProfilePhotoUseCaseProtocol
    let translationService: (any TranslationServiceProtocol)?

    /// Groups created from inside this community, waiting for their server id.
    ///
    /// Creation is local-first: the group exists on this device before it exists
    /// on the server, and `groups/link` needs the server's id. So the local id
    /// is parked here and the link fires on `.groupActivated`.
    private var groupsAwaitingLink: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    init(
        communityId: String,
        useCases: CommunityUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        groupUseCases: GroupUseCasesProtocol,
        uploadAvatar: UploadProfilePhotoUseCaseProtocol,
        translationService: (any TranslationServiceProtocol)?
    ) {
        self.communityId = communityId
        self.useCases = useCases
        self.discussionUseCases = discussionUseCases
        self.groupUseCases = groupUseCases
        self.uploadAvatar = uploadAvatar
        self.translationService = translationService
        observeGroupActivation()
    }

    /// What was last said in a group, when the inbox has that conversation.
    func preview(for group: CommunityGroupSummary) -> ConversationPreview? {
        guard let conversationId = group.conversationId else { return nil }
        return previews[conversationId]
    }

    // MARK: - Derived

    var announcementGroup: CommunityGroupSummary? {
        groups.first { $0.isAnnouncementGroup }
    }

    var chatGroups: [CommunityGroupSummary] {
        groups.filter { !$0.isAnnouncementGroup }
    }

    /// Sub-groups this user is actually in, and can therefore open.
    var joinedGroups: [CommunityGroupSummary] {
        chatGroups.filter { isMember(of: $0) }
    }

    /// Sub-groups in the community this user has not joined.
    ///
    /// Being in a community is not being in its groups — the integration doc is
    /// explicit about it — so these are listed apart rather than mixed in with
    /// rooms that would refuse to open.
    var joinableGroups: [CommunityGroupSummary] {
        chatGroups.filter { !isMember(of: $0) }
    }

    /// Membership is read from the roster when the server sent one, and from the
    /// inbox otherwise: a conversation this device holds is one it was made a
    /// participant of.
    private func isMember(of group: CommunityGroupSummary) -> Bool {
        let currentUserId = CurrentSessionInfo.shared.currentUid
        if group.members.contains(where: { $0.userId == currentUserId }) {
            return true
        }
        guard let conversationId = group.conversationId else { return false }
        return previews[conversationId] != nil
    }

    var myRole: CommunityRole? {
        community?.myRole
    }

    var canAdminister: Bool {
        myRole?.canAdminister ?? false
    }

    /// Members of the community, read off the announcements group.
    ///
    /// There is no route that lists community members on their own: everyone in
    /// the community is a participant of the announcements conversation, which
    /// is exactly what that group's roster is.
    var members: [CommunityMember] {
        announcementGroup?.members ?? []
    }

    // MARK: - Loading

    func onAppear() {
        Task { await load() }
    }

    func load() async {
        isLoading = community == nil
        defer { isLoading = false }

        do {
            let community = try await useCases.getCommunity.execute(communityId: communityId)
            self.community = community
            self.groups = community.groups.isEmpty
                ? try await useCases.manageGroups.groups(communityId: communityId)
                : community.groups
            previews = ConversationPreview.index(
                (try? await discussionUseCases.getDiscussions.execute()) ?? []
            )
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Conversations

    /// The conversation a group is chatted in, or nil with `errorMessage` set
    /// when Core has not provisioned it yet.
    func conversationId(for group: CommunityGroupSummary) async -> String? {
        do {
            return try await useCases.openConversation.execute(
                communityId: communityId,
                groupId: group.id
            )
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    // MARK: - Membership

    func leave() async {
        await perform {
            _ = try await self.useCases.leaveCommunity.execute(communityId: self.communityId)
            self.didLeave = true
        }
    }

    func delete() async {
        await perform {
            try await self.useCases.deleteCommunity.execute(communityId: self.communityId)
            self.didLeave = true
        }
    }

    // MARK: - Members

    func updateRole(userId: String, to role: CommunityRole) async {
        await perform {
            try await self.useCases.manageMembers.updateRole(
                communityId: self.communityId,
                userId: userId,
                role: role
            )
            await self.load()
        }
    }

    func removeMember(userId: String) async {
        await perform {
            try await self.useCases.manageMembers.remove(
                communityId: self.communityId,
                userId: userId
            )
            await self.load()
        }
    }

    func transferOwnership(to userId: String) async {
        await perform {
            try await self.useCases.manageMembers.transferOwnership(
                communityId: self.communityId,
                newOwnerUserId: userId
            )
            await self.load()
        }
    }

    // MARK: - Groups

    func detach(_ group: CommunityGroupSummary) async {
        await perform {
            try await self.useCases.manageGroups.detach(
                communityId: self.communityId,
                groupId: group.id,
                isAnnouncementGroup: group.isAnnouncementGroup
            )
            await self.load()
        }
    }

    /// Joins a sub-group. Community membership is not group membership — the
    /// integration doc is explicit — so this is its own call, mocked until
    /// Identity exposes it.
    func join(_ group: CommunityGroupSummary) async {
        await perform {
            try await self.useCases.manageGroups.join(
                communityId: self.communityId,
                groupId: group.id
            )
            await self.load()
        }
    }

    // MARK: - Adding groups

    /// Groups this user can attach: their own, synced, and not already in.
    ///
    /// Active only, and not for tidiness: a group that has not synced has no
    /// server id, and `groups/link` is keyed on the server id — an unsynced
    /// group is not merely untidy in this list, it is unlinkable.
    func loadLinkableGroups() async {
        let currentUserId = CurrentSessionInfo.shared.currentUid
        let alreadyIn = Set(groups.map(\.id))

        do {
            let all = try await groupUseCases.listGroups.execute()
            linkableGroups = all.filter { group in
                guard group.canOpenDiscussion else { return false }
                guard let serverGroupId = group.resolvedGroupId, !serverGroupId.isEmpty else { return false }
                guard !alreadyIn.contains(serverGroupId) else { return false }
                return group.createdBy == currentUserId
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Attaches a group the user already owns.
    func attach(_ group: GroupChat) async {
        guard let serverGroupId = group.resolvedGroupId, !serverGroupId.isEmpty else {
            errorMessage = CommunityError.conversationNotProvisioned.errorDescription
            return
        }

        await perform {
            try await self.useCases.manageGroups.attach(
                communityId: self.communityId,
                groupId: serverGroupId
            )
            await self.load()
            await self.loadLinkableGroups()
        }
    }

    /// Creates a group and attaches it once the server has acknowledged it.
    ///
    /// The two halves cannot be one call: creation is local-first and returns
    /// before the group has a server id. The link is fired from
    /// `.groupActivated`, so a group created offline joins the community as soon
    /// as it syncs rather than failing outright.
    func createGroupAndAttach(
        name: String,
        members: [UserContactProps],
        image: UIImage?,
        settings: GroupSettings
    ) async {
        await perform {
            // The picked photo is uploaded first, the same way group creation
            // does it everywhere else. A failed upload costs the picture, not
            // the group.
            var avatarUrl: String?
            if let image {
                if case .success(let url) = await self.uploadAvatar.execute(
                    imageData: ChatImageSendEncoder.encodeAvatar(image)
                ) {
                    avatarUrl = url
                }
            }

            let input = CreateGroupWithDiscussionInput(
                groupName: name,
                invitedMembers: members,
                avatarUrl: avatarUrl,
                settings: settings
            )
            let result = try await self.groupUseCases.createGroup.execute(input)

            if let serverGroupId = result.group.resolvedGroupId, !serverGroupId.isEmpty {
                try await self.useCases.manageGroups.attach(
                    communityId: self.communityId,
                    groupId: serverGroupId
                )
                await self.load()
            } else {
                self.groupsAwaitingLink.insert(result.group.localId)
            }
        }
    }

    /// Links the groups that were created here as soon as they get their id.
    private func observeGroupActivation() {
        NotificationCenter.default.publisher(for: .groupActivated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let localId = notification.userInfo?["localId"] as? String,
                      let serverId = notification.userInfo?["serverId"] as? String,
                      self.groupsAwaitingLink.remove(localId) != nil
                else { return }

                Task { @MainActor in
                    await self.perform {
                        try await self.useCases.manageGroups.attach(
                            communityId: self.communityId,
                            groupId: serverId
                        )
                        await self.load()
                    }
                }
            }
            .store(in: &cancellables)
    }

    func attachGroup(groupId: String) async {
        await perform {
            try await self.useCases.manageGroups.attach(
                communityId: self.communityId,
                groupId: groupId
            )
            await self.load()
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Private

    private func perform(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await work()
            errorMessage = nil
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        (error as? CommunityError)?.errorDescription ?? error.localizedDescription
    }
}
