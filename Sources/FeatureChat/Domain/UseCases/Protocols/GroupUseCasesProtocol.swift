import Foundation

// MARK: - Create Group Use Case

public protocol CreateGroupUseCaseProtocol {
    /// Persists a pre-built group and starts background sync.
    func execute(_ group: GroupChat) async throws -> GroupChat
    /// Builds the group, syncs it, and creates the inbox discussion.
    func execute(_ input: CreateGroupWithDiscussionInput) async throws -> CreateGroupWithDiscussionResult
}

// MARK: - Get Group Use Case

public protocol GetGroupUseCaseProtocol {
    func execute(groupId: String) async throws -> GroupChat?
}

// MARK: - Update Group Use Case

public protocol UpdateGroupUseCaseProtocol {
    func execute(_ group: GroupChat) async throws
}

// MARK: - Update Group Info Use Case

public protocol UpdateGroupInfoUseCaseProtocol {
    func execute(_ group: GroupChat) async throws
}

// MARK: - Delete Group Use Case

public protocol DeleteGroupUseCaseProtocol {
    func execute(groupId: String) async throws
}

// MARK: - Validate Group Deletion Use Case

public protocol ValidateGroupDeletionUseCaseProtocol {
    func execute(groupId: String, currentUserId: String) async throws -> DeletionEligibility
}

// MARK: - Validate and Delete Discussion Use Case

public protocol ValidateAndDeleteDiscussionUseCaseProtocol {
    func execute(discussionId: String, currentUserId: String) async throws -> DeletionResult
}

// MARK: - Activate Group Use Case

public protocol ActivateGroupUseCaseProtocol {
    func execute(localId: String, serverId: String) async throws
}

// MARK: - Get Pending Groups Use Case

public protocol GetPendingGroupsUseCaseProtocol {
    func execute() async throws -> [GroupChat]
}

// MARK: - Retry Failed Groups Use Case

public protocol RetryFailedGroupsUseCaseProtocol {
    func execute() async throws
}

// MARK: - Retry Single Group Use Case

public protocol RetrySingleGroupUseCaseProtocol {
    func execute(_ group: GroupChat) async throws
}

// MARK: - Reset Stuck Syncing Groups Use Case

public protocol ResetStuckSyncingGroupsUseCaseProtocol {
    func execute() async throws
}

// MARK: - Add Member Use Case

public protocol AddGroupMemberUseCaseProtocol {
    func execute(member: GroupMember, to groupId: String, ownerId: String) async throws
}

// MARK: - Remove Member Use Case

public protocol RemoveGroupMemberUseCaseProtocol {
    func execute(userId: String, from groupId: String, ownerId: String) async throws
}

// MARK: - Update Member Role Use Case

public protocol UpdateMemberRoleUseCaseProtocol {
    func execute(member: GroupMember, in groupId: String, ownerId: String) async throws
}

// MARK: - Get Discussion Deletion Eligibility Use Case

public protocol GetDiscussionDeletionEligibilityUseCaseProtocol {
    func execute(discussionId: String, currentUserId: String) async throws -> DeletionEligibility
}

// MARK: - Leave Group Use Case

public protocol LeaveGroupUseCaseProtocol {
    func execute(groupId: String, userId: String) async throws -> LeaveGroupOutcome
}

// MARK: - Delete Local Group Copy Use Case

public protocol DeleteLocalGroupCopyUseCaseProtocol {
    func execute(groupId: String) async throws
}

// MARK: - List Groups Use Case

public protocol ListGroupsUseCaseProtocol {
    func execute() async throws -> [GroupChat]
}

// MARK: - Join Request Use Cases

public protocol FetchPendingJoinRequestsUseCaseProtocol {
    func execute(groupId: String) async throws -> [GroupJoinRequest]
}

public protocol SyncJoinRequestsUseCaseProtocol {
    func execute(groupId: String) async throws -> [GroupJoinRequest]
}

public protocol ApproveJoinRequestUseCaseProtocol {
    func execute(requestId: String, groupId: String, ownerId: String) async throws
}

public protocol DeclineJoinRequestUseCaseProtocol {
    func execute(requestId: String, groupId: String, ownerId: String) async throws
}

public protocol IngestJoinRequestUseCaseProtocol {
    func execute(_ request: GroupJoinRequest, groupId: String) async throws
}

public protocol ReconcileJoinRequestsUseCaseProtocol {
    func execute(groupId: String) async throws -> [GroupJoinRequest]
}

// MARK: - Group Invite Link Use Cases

public protocol CreateGroupInviteLinkUseCaseProtocol {
    func execute(groupId: String) async throws -> InviteDataDTO
}

public protocol RegenerateGroupInviteLinkUseCaseProtocol {
    func execute(groupId: String) async throws -> InviteDataDTO
}

// MARK: - Container Protocol

public protocol GroupUseCasesProtocol {
    var createGroup: CreateGroupUseCaseProtocol { get }
    var getGroup: GetGroupUseCaseProtocol { get }
    var updateGroup: UpdateGroupUseCaseProtocol { get }
    var updateGroupInfo: UpdateGroupInfoUseCaseProtocol { get }
    var deleteGroup: DeleteGroupUseCaseProtocol { get }
    var validateGroupDeletion: ValidateGroupDeletionUseCaseProtocol { get }
    var getDiscussionDeletionEligibility: GetDiscussionDeletionEligibilityUseCaseProtocol { get }
    var validateAndDeleteDiscussion: ValidateAndDeleteDiscussionUseCaseProtocol { get }
    var activateGroup: ActivateGroupUseCaseProtocol { get }
    var getPendingGroups: GetPendingGroupsUseCaseProtocol { get }
    var retryFailedGroups: RetryFailedGroupsUseCaseProtocol { get }
    var retrySingleGroup: RetrySingleGroupUseCaseProtocol { get }
    var resetStuckSyncingGroups: ResetStuckSyncingGroupsUseCaseProtocol { get }
    var addMember: AddGroupMemberUseCaseProtocol { get }
    var removeMember: RemoveGroupMemberUseCaseProtocol { get }
    var updateMemberRole: UpdateMemberRoleUseCaseProtocol { get }
    var leaveGroup: LeaveGroupUseCaseProtocol { get }
    var deleteLocalGroupCopy: DeleteLocalGroupCopyUseCaseProtocol { get }
    var listGroups: ListGroupsUseCaseProtocol { get }
    var fetchPendingJoinRequests: FetchPendingJoinRequestsUseCaseProtocol { get }
    var syncJoinRequests: SyncJoinRequestsUseCaseProtocol { get }
    var approveJoinRequest: ApproveJoinRequestUseCaseProtocol { get }
    var declineJoinRequest: DeclineJoinRequestUseCaseProtocol { get }
    var ingestJoinRequest: IngestJoinRequestUseCaseProtocol { get }
    var reconcileJoinRequests: ReconcileJoinRequestsUseCaseProtocol { get }
    var createInviteLink: CreateGroupInviteLinkUseCaseProtocol { get }
    var regenerateInviteLink: RegenerateGroupInviteLinkUseCaseProtocol { get }
}
