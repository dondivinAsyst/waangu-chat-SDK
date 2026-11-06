import Foundation
import WaanguCoreKit

// MARK: - Create Group Use Case

final class CreateGroupUseCase: CreateGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    private let discussionRepository: DiscussionRepositoryProtocol

    init(
        repository: GroupRepositoryProtocol,
        discussionRepository: DiscussionRepositoryProtocol
    ) {
        self.repository = repository
        self.discussionRepository = discussionRepository
    }

    func execute(_ group: GroupChat) async throws -> GroupChat {
        try await repository.createGroupWithSync(group)
    }

    func execute(_ input: CreateGroupWithDiscussionInput) async throws -> CreateGroupWithDiscussionResult {
        let trimmedName = input.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CreateGroupError.emptyGroupName
        }

        let group = GroupChat(
            localId: UUID().uuidString.lowercased(),
            serverId: nil,
            isPendingCreation: true,
            isActive: false,
            syncStatus: .pending,
            name: trimmedName,
            description: nil,
            avatarUrl: input.avatarUrl,
            createdBy: CurrentSessionInfo.shared.currentUid,
            members: Self.buildMembers(from: input.invitedMembers),
            settings: input.settings
        )

        let persistedGroup = try await repository.createGroupWithSync(group)
        
        // ✅ FIX: Don't create discussion yet - it will be created when group sync succeeds
        // Discussion creation happens via .groupActivated notification
        // This prevents discussions for failed/pending groups
        
        return CreateGroupWithDiscussionResult(
            group: persistedGroup,
            discussion: nil  // Will be created on successful sync
        )
    }

    private static func buildMembers(from invited: [UserContactProps]) -> [GroupMember] {
        let currentUid = CurrentSessionInfo.shared.currentUid

        let creator = GroupMember(
            userId: currentUid,
            name: CurrentSessionInfo.shared.userName,
            phone: CurrentSessionInfo.shared.userPhoneNumber,
            avatar: CurrentSessionInfo.shared.userProfile,
            role: .ADMIN
        )

        var seen = Set<String>([currentUid])
//        var members:[GroupMember] = []
        var members = [creator]

        for contact in invited {
            guard !seen.contains(contact.userId) else { continue }
            seen.insert(contact.userId)
            members.append(
                GroupMember(
                    userId: contact.userId,
                    name: contact.name,
                    phone: contact.phone,
                    avatar: contact.avatar,
                    role: .MEMBER
                )
            )
        }
debugLog("this is the real one  \(members)")
        return members
    }

    private static func makeDiscussion(
        group: GroupChat,
        groupName: String,
        avatarUrl: String?
    ) -> DiscussionChatItem {
        let systemMessage = MessageDataItem(
            codeMessage: UUID().uuidString.lowercased(),
            senderId: CurrentSessionInfo.shared.currentUid,
            senderPhone: CurrentSessionInfo.shared.userPhoneNumber,
            senderName: CurrentSessionInfo.shared.userName,
            receiverId: group.localId,
            groupId: group.localId,
            typeMessage: .GROUP_CREATED,
            message: MessageContent(text: "Group created"),
            status: .DELIVERED,
            createdAt: Date()
        )

        let contact = ContactChannel(
            userName: groupName,
            phone: "",
            image: avatarUrl,
            isBlocked: false,
            isGroup: true,
            id: group.localId
        )

        return DiscussionChatItem(
            lastMessage: systemMessage,
            conversationId: group.localId,
            contact: contact,
            count: 0
        )
    }
}

// MARK: - Get Group Use Case

final class GetGroupUseCase: GetGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(groupId: String) async throws -> GroupChat? {
        if let group = try await repository.getGroupByServerId(groupId) {
            return group
        }
        return try await repository.getGroupByLocalId(groupId)
    }
}

// MARK: - Update Group Use Case

final class UpdateGroupUseCase: UpdateGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(_ group: GroupChat) async throws {
        try await repository.updateGroup(group)
    }
}

// MARK: - Update Group Info Use Case

final class UpdateGroupInfoUseCase: UpdateGroupInfoUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(_ group: GroupChat) async throws {
        try await repository.updateGroupWithSync(group)
    }
}

// MARK: - Validate Group Deletion Use Case

final class ValidateGroupDeletionUseCase: ValidateGroupDeletionUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(groupId: String, currentUserId: String) async throws -> DeletionEligibility {
        guard let group = try await repository.getGroup(id: groupId) else {
            throw GroupError.notFound
        }
        
        // Check if user is currently an active member
        let currentMember = group.members.first { member in
            member.userId == currentUserId
                || (!CurrentSessionInfo.shared.currentUid.isEmpty
                    && member.userId == CurrentSessionInfo.shared.currentUid)
        }
        let isMember = currentMember?.isActive ?? false
        let activeMemberCount = group.memberCount
        
        // Case 1: User is still an active member
        if isMember {
            // User is the last member - can leave and delete
            if activeMemberCount == 1 {
                return .lastMember(groupName: group.name)
            }
            
            // User is NOT the last member - must leave first
            return .stillActiveMember(groupName: group.name, memberCount: activeMemberCount)
        }
        
        // Case 2: User has already left or was never a member
        return .alreadyLeft(
            groupName: group.name,
            hasOtherMembers: activeMemberCount > 0,
            activeMemberCount: activeMemberCount
        )
    }
}

// MARK: - Delete Group Use Case

final class DeleteGroupUseCase: DeleteGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(groupId: String) async throws {
        try await repository.deleteGroup(id: groupId)
        
        NotificationCenter.default.post(
            name: .groupDeleted,
            object: nil,
            userInfo: ["groupId": groupId]
        )
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }
}

// MARK: - Validate and Delete Discussion Use Case

final class ValidateAndDeleteDiscussionUseCase: ValidateAndDeleteDiscussionUseCaseProtocol {
    private let discussionRepository: DiscussionRepositoryProtocol
    private let groupRepository: GroupRepositoryProtocol
    private let validateDeletion: ValidateGroupDeletionUseCaseProtocol
    
    init(
        discussionRepository: DiscussionRepositoryProtocol,
        groupRepository: GroupRepositoryProtocol,
        validateDeletion: ValidateGroupDeletionUseCaseProtocol
    ) {
        self.discussionRepository = discussionRepository
        self.groupRepository = groupRepository
        self.validateDeletion = validateDeletion
    }
    
    func execute(discussionId: String, currentUserId: String) async throws -> DeletionResult {
        guard let discussion = try await discussionRepository.getDiscussionById(conversationId: discussionId) else {
            return .error(message: "Discussion not found")
        }
        
        guard discussion.contact?.isGroup == true else {
            try await discussionRepository.deleteDiscussion(conversationId: discussionId)
            return .success
        }
        
        let eligibility = try await validateDeletion.execute(
            groupId: discussionId,
            currentUserId: currentUserId
        )
        
        switch eligibility.suggestedAction {
        case .deleteNow:
            try await discussionRepository.deleteDiscussion(conversationId: discussionId)
            return .success
            
        case .deleteLocalContent:
            if eligibility.metadata.isMember {
                try await discussionRepository.deleteAllDiscussionMessages(conversationId: discussionId)
            } else {
                try await groupRepository.deleteGroup(id: discussionId)
                try await discussionRepository.deleteDiscussion(conversationId: discussionId)
            }
            return .success
            
        case .leaveGroupFirst, .leaveAndDelete:
            return .requiresLeave(groupId: discussionId)
            
        case .cannotDelete:
            return .blocked(reason: eligibility.userMessage)
        }
    }
}

// MARK: - Get Discussion Deletion Eligibility Use Case

final class GetDiscussionDeletionEligibilityUseCase: GetDiscussionDeletionEligibilityUseCaseProtocol {
    private let discussionRepository: DiscussionRepositoryProtocol
    private let validateDeletion: ValidateGroupDeletionUseCaseProtocol
    
    init(
        discussionRepository: DiscussionRepositoryProtocol,
        validateDeletion: ValidateGroupDeletionUseCaseProtocol
    ) {
        self.discussionRepository = discussionRepository
        self.validateDeletion = validateDeletion
    }
    
    func execute(discussionId: String, currentUserId: String) async throws -> DeletionEligibility {
        guard let discussion = try await discussionRepository.getDiscussionById(conversationId: discussionId) else {
            throw GroupError.notFound
        }
        
        guard discussion.contact?.isGroup == true else {
            return .regularDiscussion()
        }
        
        return try await validateDeletion.execute(groupId: discussionId, currentUserId: currentUserId)
    }
}

// MARK: - Activate Group Use Case

final class ActivateGroupUseCase: ActivateGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(localId: String, serverId: String) async throws {
        try await repository.activateGroup(localId: localId, serverId: serverId)
    }
}

// MARK: - Get Pending Groups Use Case

final class GetPendingGroupsUseCase: GetPendingGroupsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws -> [GroupChat] {
        try await repository.getPendingGroups()
    }
}

// MARK: - Retry Failed Groups Use Case

final class RetryFailedGroupsUseCase: RetryFailedGroupsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    private let maxRetries = 3
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws {
        let pendingGroups = try await repository.getPendingGroups()
        
        for group in pendingGroups where group.syncStatus == .failed && group.retryCount < maxRetries {
            do {
                debugLog("this wwas  group \(group)")
                try await repository.retryPendingGroupSync(group)
              
            } catch {
                debugLog("this wwas failed -----  \(error.localizedDescription)")
                try? await repository.markSyncFailed(
                    localId: group.localId,
                    error: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - Retry Single Group Use Case

final class RetrySingleGroupUseCase: RetrySingleGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(_ group: GroupChat) async throws {
        debugLog("PendingGroupRow retry 22")
        try await repository.retryPendingGroupSync(group)
    }
}

// MARK: - Reset Stuck Syncing Groups Use Case

final class ResetStuckSyncingGroupsUseCase: ResetStuckSyncingGroupsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws {
        try await repository.resetStuckSyncingGroups()
    }
}

// MARK: - Add Member Use Case

final class AddGroupMemberUseCase: AddGroupMemberUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(member: GroupMember, to groupId: String, ownerId: String) async throws {
        try await repository.addMemberWithSync(member, to: groupId, ownerId: ownerId)
    }
}

// MARK: - Remove Member Use Case

final class RemoveGroupMemberUseCase: RemoveGroupMemberUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(userId: String, from groupId: String, ownerId: String) async throws {
        try await repository.removeMemberWithSync(userId: userId, from: groupId, ownerId: ownerId)
    }
}

// MARK: - Update Member Role Use Case

final class UpdateMemberRoleUseCase: UpdateMemberRoleUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(member: GroupMember, in groupId: String, ownerId: String) async throws {
        try await repository.updateMemberRoleWithSync(member, in: groupId, ownerId: ownerId)
    }
}

// MARK: - Leave Group Use Case

final class LeaveGroupUseCase: LeaveGroupUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(groupId: String, userId: String) async throws -> LeaveGroupOutcome {
        try await repository.leaveGroupWithSync(groupId: groupId, userId: userId)
        return .left
    }
}

// MARK: - Delete Local Group Copy Use Case

final class DeleteLocalGroupCopyUseCase: DeleteLocalGroupCopyUseCaseProtocol {
    private let discussionRepository: DiscussionRepositoryProtocol
    private let groupRepository: GroupRepositoryProtocol
    
    init(
        discussionRepository: DiscussionRepositoryProtocol,
        groupRepository: GroupRepositoryProtocol
    ) {
        self.discussionRepository = discussionRepository
        self.groupRepository = groupRepository
    }
    
    func execute(groupId: String) async throws {
        try await groupRepository.deleteGroup(id: groupId)
        try await discussionRepository.deleteDiscussion(conversationId: groupId)
        
        NotificationCenter.default.post(
            name: .groupDeleted,
            object: nil,
            userInfo: ["groupId": groupId]
        )
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }
}

// MARK: - Join Request Use Cases

final class FetchPendingJoinRequestsUseCase: FetchPendingJoinRequestsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupId: String) async throws -> [GroupJoinRequest] {
        try await repository.fetchPendingJoinRequests(groupId: groupId)
    }
}

final class SyncJoinRequestsUseCase: SyncJoinRequestsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupId: String) async throws -> [GroupJoinRequest] {
        try await repository.syncJoinRequests(groupId: groupId)
    }
}

final class ApproveJoinRequestUseCase: ApproveJoinRequestUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(requestId: String, groupId: String, ownerId: String) async throws {
        try await repository.approveJoinRequest(
            requestId: requestId,
            groupId: groupId,
            ownerId: ownerId
        )
    }
}

final class DeclineJoinRequestUseCase: DeclineJoinRequestUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(requestId: String, groupId: String, ownerId: String) async throws {
        try await repository.declineJoinRequest(
            requestId: requestId,
            groupId: groupId,
            ownerId: ownerId
        )
    }
}

final class IngestJoinRequestUseCase: IngestJoinRequestUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(_ request: GroupJoinRequest, groupId: String) async throws {
        try await repository.ingestJoinRequest(request, groupId: groupId)
    }
}

final class ReconcileJoinRequestsUseCase: ReconcileJoinRequestsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupId: String) async throws -> [GroupJoinRequest] {
        try await repository.reconcileJoinRequestsFromStore(groupId: groupId)
    }
}

// MARK: - Create Group Invite Link Use Case

final class CreateGroupInviteLinkUseCase: CreateGroupInviteLinkUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupId: String) async throws -> InviteDataDTO {
        try await repository.createInviteLink(groupId: groupId)
    }
}

// MARK: - Regenerate Group Invite Link Use Case

final class RegenerateGroupInviteLinkUseCase: RegenerateGroupInviteLinkUseCaseProtocol {
    private let repository: GroupRepositoryProtocol

    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupId: String) async throws -> InviteDataDTO {
        // For now, regenerating is the same as creating a new link
        // The backend will invalidate the old link and create a new one
        try await repository.createInviteLink(groupId: groupId)
    }
}

// MARK: - List Groups Use Case

final class ListGroupsUseCase: ListGroupsUseCaseProtocol {
    private let repository: GroupRepositoryProtocol
    
    init(repository: GroupRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws -> [GroupChat] {
        try await repository.getAllGroups()
    }
}

// MARK: - Group Use Cases Container

final class GroupUseCases: GroupUseCasesProtocol {
    let createGroup: CreateGroupUseCaseProtocol
    let getGroup: GetGroupUseCaseProtocol
    let updateGroup: UpdateGroupUseCaseProtocol
    let updateGroupInfo: UpdateGroupInfoUseCaseProtocol
    let deleteGroup: DeleteGroupUseCaseProtocol
    let validateGroupDeletion: ValidateGroupDeletionUseCaseProtocol
    let getDiscussionDeletionEligibility: GetDiscussionDeletionEligibilityUseCaseProtocol
    let validateAndDeleteDiscussion: ValidateAndDeleteDiscussionUseCaseProtocol
    let activateGroup: ActivateGroupUseCaseProtocol
    let getPendingGroups: GetPendingGroupsUseCaseProtocol
    let retryFailedGroups: RetryFailedGroupsUseCaseProtocol
    let retrySingleGroup: RetrySingleGroupUseCaseProtocol
    let resetStuckSyncingGroups: ResetStuckSyncingGroupsUseCaseProtocol
    let addMember: AddGroupMemberUseCaseProtocol
    let removeMember: RemoveGroupMemberUseCaseProtocol
    let updateMemberRole: UpdateMemberRoleUseCaseProtocol
    let leaveGroup: LeaveGroupUseCaseProtocol
    let deleteLocalGroupCopy: DeleteLocalGroupCopyUseCaseProtocol
    let listGroups: ListGroupsUseCaseProtocol
    let fetchPendingJoinRequests: FetchPendingJoinRequestsUseCaseProtocol
    let syncJoinRequests: SyncJoinRequestsUseCaseProtocol
    let approveJoinRequest: ApproveJoinRequestUseCaseProtocol
    let declineJoinRequest: DeclineJoinRequestUseCaseProtocol
    let ingestJoinRequest: IngestJoinRequestUseCaseProtocol
    let reconcileJoinRequests: ReconcileJoinRequestsUseCaseProtocol
    let createInviteLink: CreateGroupInviteLinkUseCaseProtocol
    let regenerateInviteLink: RegenerateGroupInviteLinkUseCaseProtocol

    init(
        repository: GroupRepositoryProtocol,
        discussionRepository: DiscussionRepositoryProtocol
    ) {
        self.createGroup = CreateGroupUseCase(
            repository: repository,
            discussionRepository: discussionRepository
        )
        self.getGroup = GetGroupUseCase(repository: repository)
        self.updateGroup = UpdateGroupUseCase(repository: repository)
        self.updateGroupInfo = UpdateGroupInfoUseCase(repository: repository)
        self.deleteGroup = DeleteGroupUseCase(repository: repository)
        let validateGroupDeletion = ValidateGroupDeletionUseCase(repository: repository)
        self.validateGroupDeletion = validateGroupDeletion
        self.getDiscussionDeletionEligibility = GetDiscussionDeletionEligibilityUseCase(
            discussionRepository: discussionRepository,
            validateDeletion: validateGroupDeletion
        )
        self.validateAndDeleteDiscussion = ValidateAndDeleteDiscussionUseCase(
            discussionRepository: discussionRepository,
            groupRepository: repository,
            validateDeletion: validateGroupDeletion
        )
        self.activateGroup = ActivateGroupUseCase(repository: repository)
        self.getPendingGroups = GetPendingGroupsUseCase(repository: repository)
        self.retryFailedGroups = RetryFailedGroupsUseCase(repository: repository)
        self.retrySingleGroup = RetrySingleGroupUseCase(repository: repository)
        self.resetStuckSyncingGroups = ResetStuckSyncingGroupsUseCase(repository: repository)
        self.addMember = AddGroupMemberUseCase(repository: repository)
        self.removeMember = RemoveGroupMemberUseCase(repository: repository)
        self.updateMemberRole = UpdateMemberRoleUseCase(repository: repository)
        self.leaveGroup = LeaveGroupUseCase(repository: repository)
        self.deleteLocalGroupCopy = DeleteLocalGroupCopyUseCase(
            discussionRepository: discussionRepository,
            groupRepository: repository
        )
        self.listGroups = ListGroupsUseCase(repository: repository)
        self.fetchPendingJoinRequests = FetchPendingJoinRequestsUseCase(repository: repository)
        self.syncJoinRequests = SyncJoinRequestsUseCase(repository: repository)
        self.approveJoinRequest = ApproveJoinRequestUseCase(repository: repository)
        self.declineJoinRequest = DeclineJoinRequestUseCase(repository: repository)
        self.ingestJoinRequest = IngestJoinRequestUseCase(repository: repository)
        self.reconcileJoinRequests = ReconcileJoinRequestsUseCase(repository: repository)
        self.createInviteLink = CreateGroupInviteLinkUseCase(repository: repository)
        self.regenerateInviteLink = RegenerateGroupInviteLinkUseCase(repository: repository)
    }
}
