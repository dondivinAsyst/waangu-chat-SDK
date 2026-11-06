//
//  CommunityRepository.swift
//  FeatureChat
//
//  Remote-backed, with the last read kept in memory.
//

import Foundation
import WaanguCoreKit

/// Communities live on Identity; this keeps the last read so a tab switch does
/// not refetch, and nothing else. There is no local table: the conversations a
/// community owns are already persisted by the conversation sync, and the
/// metadata around them is small and cheap to refetch.
actor CommunityRepository: CommunityRepositoryProtocol {

    private let remoteDataSource: RemoteCommunityDataSourceProtocol
    private let logger: any AppLoggerProtocol

    /// Last successful `myCommunities`. Nil means "never fetched", which is not
    /// the same as "fetched and empty".
    private var cachedMine: [Community]?

    init(
        remoteDataSource: RemoteCommunityDataSourceProtocol,
        logger: any AppLoggerProtocol
    ) {
        self.remoteDataSource = remoteDataSource
        self.logger = logger
    }

    // MARK: - Read

    func myCommunities(refresh: Bool) async throws -> [Community] {
        if !refresh, let cachedMine {
            return cachedMine
        }

        do {
            let dtos = try await remoteDataSource.listMyCommunities(page: 0, size: Self.pageSize)
            let communities = dtos.map { CommunityMapper.toDomain($0) }
            cachedMine = communities
            return communities
        } catch {
            throw await mapped(error, context: "myCommunities")
        }
    }

    func discoverCommunities(page: Int, size: Int) async throws -> [Community] {
        do {
            let dtos = try await remoteDataSource.listCommunities(page: page, size: size)
            return dtos.map { CommunityMapper.toDomain($0) }
        } catch {
            throw await mapped(error, context: "discoverCommunities")
        }
    }

    func community(id: String) async throws -> Community {
        do {
            let dto = try await remoteDataSource.getCommunity(id: id)
            var community = CommunityMapper.toDomain(dto)

            // `/byId` does not always carry the groups, and the screens that ask
            // for a community are the ones that need them.
            if community.groups.isEmpty {
                community.groups = (try? await groups(communityId: id)) ?? []
                if community.announcementGroupId == nil {
                    community.announcementGroupId = community.announcementGroup?.id
                }
            }

            replaceInCache(community)
            return community
        } catch {
            throw await mapped(error, context: "community(id:)")
        }
    }

    // MARK: - Write

    func create(_ draft: NewCommunityDraft) async throws -> Community {
        do {
            let dto = try await remoteDataSource.createCommunity(CommunityMapper.toRequest(draft))
            let community = CommunityMapper.toDomain(dto)
            cachedMine = (cachedMine ?? []) + [community]
            return community
        } catch {
            throw await mapped(error, context: "create")
        }
    }

    func update(
        communityId: String,
        name: String?,
        description: String?,
        image: String?
    ) async throws -> Community {
        do {
            let dto = try await remoteDataSource.updateCommunity(
                UpdateCommunityRequest(
                    communityId: communityId,
                    name: name,
                    description: description,
                    image: image
                )
            )
            let community = CommunityMapper.toDomain(dto)
            replaceInCache(community)
            return community
        } catch {
            throw await mapped(error, context: "update")
        }
    }

    func delete(communityId: String) async throws {
        do {
            try await remoteDataSource.deleteCommunity(CommunityIdRequest(communityId: communityId))
            cachedMine?.removeAll { $0.id == communityId }
        } catch {
            throw await mapped(error, context: "delete")
        }
    }

    // MARK: - Membership

    func join(communityId: String) async throws -> CommunityMembershipOutcome {
        try await join(.joining(communityId: communityId), communityId: communityId)
    }

    func join(inviteCode: String) async throws -> CommunityMembershipOutcome {
        try await join(.joining(inviteCode: inviteCode), communityId: nil)
    }

    func leave(communityId: String) async throws -> CommunityMembershipOutcome {
        do {
            try await remoteDataSource.changeMembership(.leaving(communityId: communityId))
            cachedMine?.removeAll { $0.id == communityId }
            return .left(communityId: communityId)
        } catch {
            throw await mapped(error, context: "leave")
        }
    }

    // MARK: - Member administration

    func addMember(communityId: String, userId: String, userName: String) async throws {
        do {
            try await remoteDataSource.addMember(
                AddCommunityMemberRequest(communityId: communityId, userId: userId, userName: userName)
            )
            invalidateCache()
        } catch {
            throw await mapped(error, context: "addMember")
        }
    }

    func removeMember(communityId: String, userId: String) async throws {
        do {
            try await remoteDataSource.removeMember(
                RemoveCommunityMemberRequest(communityId: communityId, userId: userId)
            )
            invalidateCache()
        } catch {
            throw await mapped(error, context: "removeMember")
        }
    }

    func updateRole(communityId: String, userId: String, role: CommunityRole) async throws {
        do {
            try await remoteDataSource.updateMemberRole(
                UpdateCommunityMemberRoleRequest(
                    communityId: communityId,
                    userId: userId,
                    role: role.rawValue
                )
            )
            invalidateCache()
        } catch {
            throw await mapped(error, context: "updateRole")
        }
    }

    func transferOwnership(communityId: String, newOwnerUserId: String) async throws {
        do {
            try await remoteDataSource.transferOwner(
                TransferCommunityOwnerRequest(communityId: communityId, newOwnerUserId: newOwnerUserId)
            )
            invalidateCache()
        } catch {
            throw await mapped(error, context: "transferOwnership")
        }
    }

    func groupContext(
        forConversationId conversationId: String
    ) async throws -> (community: Community, group: CommunityGroupSummary)? {
        guard !conversationId.isEmpty else { return nil }

        // The user's own communities are the only ones whose conversations they
        // can be sitting in, and they are usually already cached.
        let communities = try await myCommunities(refresh: cachedMine == nil)
        for community in communities {
            if let group = community.groups.first(where: { $0.conversationId == conversationId }) {
                return (community, group)
            }
        }
        return nil
    }

    // MARK: - Groups

    func groups(communityId: String) async throws -> [CommunityGroupSummary] {
        do {
            let dtos = try await remoteDataSource.listGroups(communityId: communityId)
            return CommunityMapper.sortedAnnouncementsFirst(dtos.map { CommunityMapper.toDomain($0) })
        } catch {
            throw await mapped(error, context: "groups")
        }
    }

    func groupMembers(communityId: String, groupId: String) async throws -> [CommunityMember] {
        do {
            let dtos = try await remoteDataSource.listGroupMembers(
                communityId: communityId,
                groupId: groupId
            )
            return dtos.compactMap { CommunityMapper.toDomain($0) }
        } catch {
            throw await mapped(error, context: "groupMembers")
        }
    }

    // MARK: - Settings and joining

    func settings(communityId: String) async throws -> CommunitySettings {
        do {
            return CommunityMapper.toDomain(
                try await remoteDataSource.settings(communityId: communityId)
            )
        } catch {
            throw await mapped(error, context: "settings")
        }
    }

    func updateSettings(communityId: String, settings: CommunitySettings) async throws {
        do {
            try await remoteDataSource.updateSettings(
                UpdateCommunitySettingsRequest(
                    communityId: communityId,
                    whoCanAddMembers: settings.whoCanAddMembers.rawValue,
                    whoCanAddGroups: settings.whoCanAddGroups.rawValue
                )
            )
        } catch {
            throw await mapped(error, context: "updateSettings")
        }
    }

    func joinGroup(communityId: String, groupId: String) async throws {
        do {
            try await remoteDataSource.joinGroup(
                JoinCommunityGroupRequest(communityId: communityId, groupId: groupId)
            )
            invalidateCache()
        } catch {
            throw await mapped(error, context: "joinGroup")
        }
    }

    func linkGroup(communityId: String, groupId: String) async throws {
        try await link(communityId: communityId, groupId: groupId, attach: true)
    }

    func unlinkGroup(communityId: String, groupId: String) async throws {
        try await link(communityId: communityId, groupId: groupId, attach: false)
    }

    // MARK: - Private

    private static let pageSize = 50

    private func join(
        _ request: CommunityMembershipRequest,
        communityId: String?
    ) async throws -> CommunityMembershipOutcome {
        do {
            try await remoteDataSource.changeMembership(request)
            // The joined community now has a conversation this device does not
            // know about; the next inbox sync brings it in.
            cachedMine = nil
            return .joined(communityId: communityId ?? "")
        } catch {
            let mappedError = await mapped(error, context: "join")
            // Already in it is where the caller wanted to be.
            if case .alreadyMember = mappedError {
                cachedMine = nil
                return .alreadyMember(communityId: communityId ?? "")
            }
            throw mappedError
        }
    }

    private func link(communityId: String, groupId: String, attach: Bool) async throws {
        do {
            try await remoteDataSource.linkGroup(
                LinkCommunityGroupRequest(communityId: communityId, groupId: groupId, attach: attach)
            )
            invalidateCache()
        } catch {
            throw await mapped(error, context: attach ? "linkGroup" : "unlinkGroup")
        }
    }

    private func replaceInCache(_ community: Community) {
        guard cachedMine != nil else { return }
        if let index = cachedMine?.firstIndex(where: { $0.id == community.id }) {
            cachedMine?[index] = community
        }
    }

    /// Drops the cache so the next read goes back to Identity.
    ///
    /// The whole list goes, not the one row: membership and role changes move
    /// counts and ranks the cached copies of the other communities may also be
    /// showing.
    private func invalidateCache() {
        cachedMine = nil
    }

    private func mapped(_ error: Error, context: String) async -> CommunityError {
        let mappedError = CommunityErrorMapper.map(error)
        await logger.log("Community \(context) failed: \(mappedError)", level: .error)
        return mappedError
    }
}
