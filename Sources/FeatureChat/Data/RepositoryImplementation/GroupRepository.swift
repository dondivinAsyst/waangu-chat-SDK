import Foundation
import WaanguCoreKit

public final class GroupRepository: GroupRepositoryProtocol {
    private let localDataSource: LocalGroupDataSourceProtocol
    private let remoteDataSource: RemoteGroupDataSourceProtocol
    private let discussionRepository: DiscussionRepositoryProtocol
    private let contactsRepository: ContactsRepositoryProtocol
    private let chatActionsUseCase: ChatActionsUseCaseProtocol?
    private let joinRequestLocalDataSource: LocalGroupJoinRequestDataSourceProtocol

    public init(
        localDataSource: LocalGroupDataSourceProtocol,
        remoteDataSource: RemoteGroupDataSourceProtocol,
        discussionRepository: DiscussionRepositoryProtocol,
        contactsRepository: ContactsRepositoryProtocol,
        chatActionsUseCase: ChatActionsUseCaseProtocol? = nil,
        joinRequestLocalDataSource: LocalGroupJoinRequestDataSourceProtocol
    ) {
        self.localDataSource = localDataSource
        self.remoteDataSource = remoteDataSource
        self.discussionRepository = discussionRepository
        self.contactsRepository = contactsRepository
        self.chatActionsUseCase = chatActionsUseCase
        self.joinRequestLocalDataSource = joinRequestLocalDataSource
    }

    /// The id the group endpoints key on.
    ///
    /// Prefers the stored group id and falls back to the conversation's server id,
    /// which is what these call sites used before the two were told apart — so a
    /// group synced under the old code keeps working unchanged.
    ///
    /// Throws rather than force-unwrapping: a group that has never reached the
    /// server has no remote id, and that is a state to report, not to crash on.
    private func remoteGroupId(_ group: GroupChat) throws -> String {
        guard let id = group.resolvedGroupId, !id.isEmpty else {
            throw GroupError.notFound
        }
        return id
    }

    func createGroup(_ group: GroupChat) async throws {
        try await localDataSource.save(group)
    }
    
    func getGroup(id: String) async throws -> GroupChat? {
        try await localDataSource.fetch(id: id)
    }
    
    func getGroupByLocalId(_ localId: String) async throws -> GroupChat? {
        try await localDataSource.fetchByLocalId(localId)
    }
    
    func getGroupByServerId(_ serverId: String) async throws -> GroupChat? {
        try await localDataSource.fetchByServerId(serverId)
    }
    
    func updateGroup(_ group: GroupChat) async throws {
        try await localDataSource.update(group)
    }
    
    func deleteGroup(id: String) async throws {
        try await localDataSource.delete(id: id)
    }
    
    func getAllGroups() async throws -> [GroupChat] {
        try await localDataSource.fetchAll()
    }
    
    func getActiveGroups() async throws -> [GroupChat] {
        try await localDataSource.fetchActive()
    }
    
    func getPendingGroups() async throws -> [GroupChat] {
        try await localDataSource.fetchPending()
    }
    
    // Commented out until type property is added back
    // func getGroupsByType(_ type: GroupType) async throws -> [GroupChat] {
    //     try await localDataSource.fetchAll().filter { $0.type == type }
    // }
    
    func createGroupWithSync(_ group: GroupChat) async throws -> GroupChat {
        // 1. Save locally first with pending status
        try await localDataSource.save(group)
        
        // 2. Start background sync
        Task {
            do {
                // ✅ Update status to syncing immediately
                var syncingGroup = group
                syncingGroup.syncStatus = .syncing
                try await localDataSource.update(syncingGroup)
                
                // Notify UI to update pending status
                NotificationCenter.default.post(
                    name: .groupSyncStatusChanged,
                    object: nil,
                    userInfo: ["localId": group.localId, "status": "syncing"]
                )
                
                // Create request from group
                let request = CreateOrUpdateGroupRequest(
                    ownerId: group.createdBy,
                    groupId: group.localId,
                    name: group.name,
                    description: group.description,
                    image: group.avatarUrl,
                    memberUserIds: group.members.filter { $0.userId != group.createdBy }.map { $0.userId },
                    settings: group.settings,
                    message: "Group created"  // ✅ Added to fix backend validation error
                )
                
                // Sync to backend
                let response = try await remoteDataSource.createGroup(request)
                
                debugLog("✅ Group sync success - localId: \(group.localId), serverId: \(response.id)")
                
                // ✅ NEW APPROACH: Keep conversationId = localId, only update serverId
                try await localDataSource.updateServerId(
                    localId: group.localId,
                    serverId: response.id
                )
                
                // Activate group (sets isActive=true, syncStatus=.synced)
                try await localDataSource.activateGroup(
                    localId: group.localId,
                    serverId: response.id
                )
                
                // ✅ Create discussion after successful sync
                await self.createDiscussionForActivatedGroup(
                    localId: group.localId,
                    groupName: group.name,
                    avatarUrl: group.avatarUrl
                )
                
                // Notify success (no need to recreate discussion)
                NotificationCenter.default.post(
                    name: .groupActivated,
                    object: nil,
                    userInfo: ["localId": group.localId, "serverId": response.id]
                )
            } catch {
                debugLog("❌ Group sync failed: \(error.localizedDescription)")
                // Mark as failed
                try? await localDataSource.markSyncFailed(
                    localId: group.localId,
                    error: error.localizedDescription
                )
                
                // ✅ Notify status changed to failed (for UI update)
                NotificationCenter.default.post(
                    name: .groupSyncStatusChanged,
                    object: nil,
                    userInfo: ["localId": group.localId, "status": "failed"]
                )
                
                // Notify failure
                NotificationCenter.default.post(
                    name: .groupSyncFailed,
                    object: nil,
                    userInfo: ["localId": group.localId, "error": error.localizedDescription]
                )
            }
        }
        
        return group
    }
    
    func retryPendingGroupSync(_ group: GroupChat) async throws {
        debugLog("PendingGroupRow retry 33")
        
        // ✅ Prevent retry if already syncing
        guard group.syncStatus != .syncing else {
            debugLog("⚠️ Group \(group.localId) is already syncing, skipping retry")
            return
        }
        
        debugLog("🔄 Retrying group sync for: \(group.localId)")
        
        do {
            // Increment retry count (doesn't change status)
            try await localDataSource.incrementRetryCount(localId: group.localId)
            
            // ✅ FIX: Explicitly set status to syncing right before network call
            // This ensures status is only .syncing during active network requests
            try await localDataSource.markSyncing(localId: group.localId)
            
            // Create request from group
            let request = CreateOrUpdateGroupRequest(
                ownerId: group.createdBy,
                groupId: group.localId,
                name: group.name,
                description: group.description,
                image: group.avatarUrl,
                memberUserIds: group.members.map { $0.userId },
                settings: group.settings,
                message: "Group created"  // ✅ Added to fix backend validation error
            )
            
            // Sync to backend
            let response = try await remoteDataSource.createGroup(request)
    //        let response = GroupResponseDto(id: group.localId, ownerId: group.createdBy, tenantId: nil, name: group.name, description: group.description, image: group.avatarUrl, icon: nil, color: nil, isDefault: nil, sortOrder: nil, memberCount: nil, teamType: nil, routingType: nil, businessHoursId: nil, autoAssignEnabled: nil, offlineRoutingEnabled: nil, offlineRoutingTo: nil, maxAssignPerAgent: nil, isActive: nil, activeConversationCount: nil, communityId: nil, isAnnouncementGroup: nil, metadata: nil, createdAt: nil, updatedAt: nil)
            debugLog("✅ Group retry success - localId: \(group.localId), serverId: \(response.id)")
            
            // ✅ NEW APPROACH: Keep conversationId = localId, only update serverId
            try await localDataSource.updateServerId(
                localId: group.localId,
                serverId: response.id
            )
            
            // Activate group with server ID
            try await localDataSource.activateGroup(
                localId: group.localId,
                serverId: response.id
            )
            
            // ✅ Create discussion after successful sync
            await self.createDiscussionForActivatedGroup(
                localId: group.localId,
                groupName: group.name,
                avatarUrl: group.avatarUrl
            )
            
            // Notify success (no need to recreate discussion)
            NotificationCenter.default.post(
                name: .groupActivated,
                object: nil,
                userInfo: ["localId": group.localId, "serverId": response.id]
            )
        } catch {
            // ✅ FIX: Reset sync status back to failed when retry fails
            // This prevents the group from staying stuck in "syncing" state
            let errorMessage = "Retry failed: \(error.localizedDescription)"
            try await localDataSource.markSyncFailed(localId: group.localId, error: errorMessage)
            
            // Notify that sync failed again
            NotificationCenter.default.post(
                name: .groupSyncFailed,
                object: nil,
                userInfo: ["localId": group.localId, "error": errorMessage]
            )
            
            debugLog("❌ Group retry failed for \(group.localId): \(error)")
            throw error // Re-throw to let the UI layer handle it
        }
    }
    
    func getGroupsForUser(_ userId: String) async throws -> [GroupChat] {
        try await localDataSource.fetchAll().filter { group in
            group.members.contains { $0.userId == userId }
        }
    }
    
    func activateGroup(localId: String, serverId: String) async throws {
        try await localDataSource.activateGroup(localId: localId, serverId: serverId)
    }
    
    func updateServerId(localId: String, serverId: String) async throws {
        try await localDataSource.updateServerId(localId: localId, serverId: serverId)
    }
    
    func markSyncFailed(localId: String, error: String) async throws {
        try await localDataSource.markSyncFailed(localId: localId, error: error)
    }
    
    func markSyncSuccess(localId: String) async throws {
        try await localDataSource.markSyncSuccess(localId: localId)
    }
    
    func incrementRetryCount(localId: String) async throws {
        try await localDataSource.incrementRetryCount(localId: localId)
    }
    
    // ✅ NEW: Reset groups stuck in syncing state on app launch
    // This fixes the issue where groups remain in "syncing" state after app restart
    // when there's no actual network request happening
    func resetStuckSyncingGroups() async throws {
        let allGroups = try await localDataSource.fetchAll()
        
        for group in allGroups where group.syncStatus == .syncing {
            debugLog("🔧 Resetting stuck syncing group: \(group.name) (\(group.localId))")
            try await localDataSource.markSyncFailed(
                localId: group.localId,
                error: "Sync interrupted - app restarted"
            )
        }
    }
    
    func addMember(_ member: GroupMember, to groupId: String) async throws {
        try await localDataSource.addMember(member, to: groupId)
    }
    
    func removeMember(userId: String, from groupId: String) async throws {
        try await localDataSource.removeMember(userId: userId, from: groupId)
    }
    
    func deactivateMember(userId: String, from groupId: String) async throws {
        try await localDataSource.deactivateMember(userId: userId, from: groupId)
    }
    
    func updateMember(_ member: GroupMember, in groupId: String) async throws {
        try await localDataSource.updateMember(member, in: groupId)
    }
    
    func updateSettings(_ settings: GroupSettings, for groupId: String) async throws {
        guard var group = try await getGroup(id: groupId) else {
            throw GroupError.notFound
        }
        group.settings = settings
        try await updateGroup(group)
    }
    
    // MARK: - Member Operations with Sync
    
    func addMemberWithSync(_ member: GroupMember, to groupId: String, ownerId: String) async throws {
        let group = try await syncedGroup(for: groupId)
        
        let request = AddGroupMembersRequest(
            ownerId: ownerId,
            groupId: try remoteGroupId(group),
            memberUserId: [member.userId]
        )
        try await remoteDataSource.addMembers(request)
        try await localDataSource.addMember(member, to: group.localId)
        
        var metadata = GroupChatActionRecorder.performerMetadata(performedBy: ownerId)
        metadata["memberName"] = member.name
        GroupChatActionRecorder.record(
            chatActionsUseCase: chatActionsUseCase,
            conversationId: group.localId,
            actionType: .memberAdded,
            performedBy: ownerId,
            targetId: member.userId,
            metadata: metadata
        )
    }
    
    func removeMemberWithSync(userId: String, from groupId: String, ownerId: String) async throws {
        let group = try await syncedGroup(for: groupId)
        guard group.members.contains(where: { $0.userId == userId }) else {
            throw GroupError.notFound
        }
        
        let member = group.members.first(where: { $0.userId == userId })
        guard member != nil else {
//            throw GroupError.notFound
            fatalError("Error occur while removing member, but member is not found")
        }
//        let contactId = try resolveContactRecordId(userId: userId, phone: member?.phone)
        let request = RemoveGroupMemberRequest(
            groupId: try remoteGroupId(group),
            userId: userId,
            ownerId: ownerId
        )
        try await remoteDataSource.removeMembers(request)
        try await localDataSource.removeMember(userId: userId, from: group.localId)
        
        var metadata = GroupChatActionRecorder.performerMetadata(performedBy: ownerId)
        metadata["memberName"] = member?.name ?? "Member"
        GroupChatActionRecorder.record(
            chatActionsUseCase: chatActionsUseCase,
            conversationId: group.localId,
            actionType: .memberRemoved,
            performedBy: ownerId,
            targetId: userId,
            metadata: metadata
        )
    }
    
    func updateMemberRoleWithSync(_ member: GroupMember, in groupId: String, ownerId: String) async throws {
        let group = try await syncedGroup(for: groupId)
        guard let existingMember = group.members.first(where: { $0.userId == member.userId }) else {
            throw GroupError.notFound
        }
        
        let request = AddGroupMemberRoleRequest(
            ownerId: ownerId,
            groupId: try remoteGroupId(group),
            userId: member.userId,
            role: member.role
        )
     
        try await remoteDataSource.updateMemberRole(request)
        try await localDataSource.updateMember(member, in: group.localId)
        
        let actionType: ChatActionType?
        if member.role == .ADMIN && existingMember.role != .ADMIN {
            actionType = .memberPromotedToAdmin
        } else if member.role == .MEMBER && existingMember.role == .ADMIN {
            actionType = .memberDemotedFromAdmin
        } else {
            actionType = nil
        }
        
        if let actionType {
            var metadata = GroupChatActionRecorder.performerMetadata(performedBy: ownerId)
            metadata["memberName"] = member.name
            GroupChatActionRecorder.record(
                chatActionsUseCase: chatActionsUseCase,
                conversationId: group.localId,
                actionType: actionType,
                performedBy: ownerId,
                targetId: member.userId,
                metadata: metadata
            )
        }
    }
    
    func leaveGroupWithSync(groupId: String, userId: String) async throws {
        let group = try await syncedGroup(for: groupId)
        guard group.members.contains(where: { $0.userId == userId && $0.isActive }) else {
            throw GroupError.notFound
        }
        
        let member = group.members.first(where: { $0.userId == userId })
        
        guard member != nil else {
            fatalError("Tried to leave a group where the user was not a member")
        }
//        let contactId = try resolveContactRecordId(
//            userId: userId,
//            phone: member?.phone ?? CurrentSessionInfo.shared.phone
//        )
        let request = LeaveGroupRequest(
            groupId: try remoteGroupId(group),
            userId: userId
        )
        try await remoteDataSource.leaveGroup(request)
        try await localDataSource.deactivateMember(userId: userId, from: group.localId)
        
        var metadata: [String: String] = [:]
        metadata["memberName"] = member?.name ?? CurrentSessionInfo.shared.userName
        GroupChatActionRecorder.record(
            chatActionsUseCase: chatActionsUseCase,
            conversationId: group.localId,
            actionType: .memberLeft,
            performedBy: userId,
            targetId: userId,
            metadata: metadata
        )
        
        NotificationCenter.default.post(
            name: .groupSyncStatusChanged,
            object: nil,
            userInfo: ["localId": group.localId]
        )
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }
    
    func updateGroupWithSync(_ group: GroupChat) async throws {
        // Store old group for potential rollback
        guard let oldGroup = try await getGroup(id: group.id) else {
            throw GroupError.notFound
        }
        
        // 1. Update locally first (optimistic update)
        try await localDataSource.update(group)
        
        // 2. Sync to backend if group is synced.
        //    Awaited, not detached: a detached Task swallows its own throw, so the
        //    caller would see success while the local write was silently rolled
        //    back underneath a UI still showing the new values.
        if let serverId = group.serverId {
            do {
                let request = UpdateGroupRequest(
                    ownerId: group.createdBy,
                    groupId: serverId,
                    name: group.name,
                    description: group.description,
                    image: group.avatarUrl,
                    settings: group.settings
                )
                _ = try await remoteDataSource.updateGroup(request)
            } catch {
                // Rollback local change on failure
                try? await localDataSource.update(oldGroup)
                throw error
            }
        }
    }
    
    // MARK: - Join Requests

    func fetchPendingJoinRequests(groupId: String) async throws -> [GroupJoinRequest] {
        do {
            return try await syncJoinRequests(groupId: groupId)
        } catch {
            return try await reconcileJoinRequestsFromStore(groupId: groupId)
        }
    }

    func syncJoinRequests(groupId: String) async throws -> [GroupJoinRequest] {
        let group = try await resolvedGroup(for: groupId)
        let serverGroupId = group.serverId ?? group.localId

        let dtos = try await remoteDataSource.fetchJoinRequests(groupId: serverGroupId)
        let requests = dtos.map { $0.toDomain(fallbackGroupId: group.localId) }

        // 1. Persist full pending set to GRDB (source of truth)
        try await joinRequestLocalDataSource.saveAll(requests, groupLocalId: group.localId)

        // 2. Derive timeline actions only from what is in the pending table
        return try await reconcileAndReturnPending(group: group)
    }

    func ingestJoinRequest(_ request: GroupJoinRequest, groupId: String) async throws {
        let group = try await resolvedGroup(for: groupId)
        try await joinRequestLocalDataSource.upsert(request, groupLocalId: group.localId)
        _ = try await reconcileAndReturnPending(group: group)
    }

    func reconcileJoinRequestsFromStore(groupId: String) async throws -> [GroupJoinRequest] {
        let group = try await resolvedGroup(for: groupId)
        return try await reconcileAndReturnPending(group: group)
    }

    func approveJoinRequest(requestId: String, groupId: String, ownerId: String) async throws {
        let group = try await syncedGroup(for: groupId)
        let request = try await resolvedJoinRequest(
            requestId: requestId,
            groupLocalId: group.localId,
            groupId: groupId
        )

        let body = ApproveJoinRequestBody(
            groupId: try remoteGroupId(group),
            requestId: requestId,
            ownerId: ownerId
        )
        try await remoteDataSource.approveJoinRequest(body)

        let member = GroupMember(
            userId: request.userId,
            name: request.name,
            phone: request.phone ?? "",
            avatar: request.avatar,
            role: .MEMBER
        )

        if !group.members.contains(where: { $0.userId == request.userId }) {
            try await localDataSource.addMember(member, to: group.localId)
        }

        try await joinRequestLocalDataSource.remove(requestId: requestId, groupLocalId: group.localId)
        await removeJoinRequestChatAction(conversationId: group.localId, requestId: requestId)

        var metadata = GroupChatActionRecorder.performerMetadata(performedBy: ownerId)
        metadata["memberName"] = request.name
        GroupChatActionRecorder.record(
            chatActionsUseCase: chatActionsUseCase,
            conversationId: group.localId,
            actionType: .memberAdded,
            performedBy: ownerId,
            targetId: request.userId,
            metadata: metadata
        )
    }

    func declineJoinRequest(requestId: String, groupId: String, ownerId: String) async throws {
        let group = try await syncedGroup(for: groupId)

        let body = DeclineJoinRequestBody(
            groupId: try remoteGroupId(group),
            requestId: requestId,
            ownerId: ownerId
        )
        try await remoteDataSource.declineJoinRequest(body)

        try await joinRequestLocalDataSource.remove(requestId: requestId, groupLocalId: group.localId)
        await removeJoinRequestChatAction(conversationId: group.localId, requestId: requestId)
    }

    // MARK: - Invite Link Operations

    func createInviteLink(groupId: String) async throws -> InviteDataDTO {
        let group = try await syncedGroup(for: groupId)
        
        let response = try await remoteDataSource.createInviteLink(groupId: try remoteGroupId(group))
        
        // Update group settings with complete invite data
        if var existingGroup = try await getGroup(id: group.localId) {
            existingGroup.settings.inviteLink = response.data.inviteLink
            existingGroup.settings.isInviteLinkActive = true
            existingGroup.settings.inviteCode = response.data.inviteCode
            existingGroup.settings.inviteExpiresAt = response.data.expiresAt
            existingGroup.settings.inviteRemainingUses = response.data.remainingUses
            try await updateGroup(existingGroup)
        }
        
        return response.data
    }

    // MARK: - Private Helpers

    private func resolvedJoinRequest(
        requestId: String,
        groupLocalId: String,
        groupId: String
    ) async throws -> GroupJoinRequest {
        if let cached = try await joinRequestLocalDataSource
            .fetchPending(groupLocalId: groupLocalId)
            .first(where: { $0.id == requestId }) {
            return cached
        }

        _ = try? await syncJoinRequests(groupId: groupId)

        if let refreshed = try await joinRequestLocalDataSource
            .fetchPending(groupLocalId: groupLocalId)
            .first(where: { $0.id == requestId }) {
            return refreshed
        }

        throw GroupError.notFound
    }

    private func resolvedGroup(for groupId: String) async throws -> GroupChat {
        if let group = try await getGroup(id: groupId) {
            return group
        }
        if let group = try await getGroupByLocalId(groupId) {
            return group
        }
        throw GroupError.notFound
    }

    /// Reads pending rows from GRDB, syncs timeline chat actions to match, returns pending list.
    private func reconcileAndReturnPending(group: GroupChat) async throws -> [GroupJoinRequest] {
        let pending = try await joinRequestLocalDataSource.fetchPending(groupLocalId: group.localId)
        await reconcileJoinRequestChatActions(group: group, requests: pending)
        return pending
    }

    /// Timeline join-request rows are always derived from the GRDB pending table — never the other way around.
    private func reconcileJoinRequestChatActions(group: GroupChat, requests: [GroupJoinRequest]) async {
        guard let chatActionsUseCase else { return }

        let existing = (try? await chatActionsUseCase.fetchActions(conversationId: group.localId)) ?? []
        let pendingIds = Set(requests.map(\.id))

        // Create a timeline checkpoint for every pending row missing a chat action
        for request in requests {
            let alreadyRecorded = existing.contains {
                $0.actionType == .joinRequestReceived && $0.targetId == request.id
            }
            guard !alreadyRecorded else { continue }

            var metadata: [String: String] = [:]
            metadata["requesterName"] = request.name
            GroupChatActionRecorder.record(
                chatActionsUseCase: chatActionsUseCase,
                conversationId: group.localId,
                actionType: .joinRequestReceived,
                performedBy: request.userId,
                targetId: request.id,
                metadata: metadata,
                timestamp: request.requestedAt
            )
        }

        // Remove orphan timeline rows that have no matching pending table entry
        for action in existing where action.actionType == .joinRequestReceived {
            guard let targetId = action.targetId, !pendingIds.contains(targetId) else { continue }
            try? await chatActionsUseCase.deleteAction(actionId: action.id)
        }
    }

    private func removeJoinRequestChatAction(conversationId: String, requestId: String) async {
        guard let chatActionsUseCase else { return }
        do {
            let actions = try await chatActionsUseCase.fetchActions(conversationId: conversationId)
            if let action = actions.first(where: {
                $0.actionType == .joinRequestReceived && $0.targetId == requestId
            }) {
                try await chatActionsUseCase.deleteAction(actionId: action.id)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .chatActionsDidChange,
                        object: nil,
                        userInfo: ["conversationId": conversationId]
                    )
                }
            }
        } catch {
            #if DEBUG
            print("Failed to remove join-request chat action: \(error)")
            #endif
        }
    }

    /// Resolves the server contact record id for group member APIs (`contactId` / `userId` body fields).
    private func resolveContactRecordId(userId: String, phone: String?) async throws -> String {
        let contacts = try await contactsRepository.fetchContacts().waanguContacts
        if let match = contacts.first(where: { $0.userId == userId }) {
            return match.id
        }
        if let phone, !phone.isEmpty,
           let match = contacts.first(where: { $0.phone == phone }) {
            return match.id
        }
        return userId
    }

    private func syncedGroup(for groupId: String) async throws -> GroupChat {
        guard let group = try await getGroup(id: groupId) else {
            throw GroupError.notFound
        }
        guard group.serverId != nil else {
            throw GroupError.syncFailed("Group has not been synced with the server yet")
        }
        return group
    }
    
    /// Creates a discussion for a successfully synced group
    private func createDiscussionForActivatedGroup(
        localId: String,
        groupName: String,
        avatarUrl: String?
    ) async {
        let contact = ContactChannel(
            userName: groupName,
            phone: "",
            image: avatarUrl,
            isBlocked: false,
            isGroup: true,
            id: localId
        )

        // Empty placeholder — group creation is shown via timeline intro + chat actions, not as a sent message.
        let placeholderLastMessage = MessageDataItem(
            codeMessage: "",
            senderId: "",
            senderPhone: "",
            senderName: "",
            receiverId: localId,
            groupId: localId,
            typeMessage: .TEXT,
            message: MessageContent(text: ""),
            status: .DELIVERED,
            createdAt: Date()
        )

        let discussion = DiscussionChatItem(
            lastMessage: placeholderLastMessage,
            conversationId: localId,
            contact: contact,
            count: 0
        )
        
        do {
            try await discussionRepository.saveDiscussion(discussion)
            debugLog("✅ Discussion created for group: \(groupName) (\(localId))")
            
            var metadata = GroupChatActionRecorder.performerMetadata(
                performedBy: CurrentSessionInfo.shared.currentUid
            )
            metadata["groupName"] = groupName
            GroupChatActionRecorder.record(
                chatActionsUseCase: chatActionsUseCase,
                conversationId: localId,
                actionType: .groupCreated,
                performedBy: CurrentSessionInfo.shared.currentUid,
                metadata: metadata
            )
        } catch {
            debugLog("❌ Failed to create discussion for group \(localId): \(error)")
        }
    }
}

