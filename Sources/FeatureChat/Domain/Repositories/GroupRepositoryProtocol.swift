import Foundation

protocol GroupRepositoryProtocol {
    // CRUD Operations
    func createGroup(_ group: GroupChat) async throws
    func createGroupWithSync(_ group: GroupChat) async throws -> GroupChat
    func getGroup(id: String) async throws -> GroupChat?
    func getGroupByLocalId(_ localId: String) async throws -> GroupChat?
    func getGroupByServerId(_ serverId: String) async throws -> GroupChat?
    func updateGroup(_ group: GroupChat) async throws
    func deleteGroup(id: String) async throws

    // Query Operations
    func getAllGroups() async throws -> [GroupChat]
    func getActiveGroups() async throws -> [GroupChat]
    func getPendingGroups() async throws -> [GroupChat]
    func getGroupsForUser(_ userId: String) async throws -> [GroupChat]

    // Sync Operations
    func retryPendingGroupSync(_ group: GroupChat) async throws
    func activateGroup(localId: String, serverId: String) async throws
    func updateServerId(localId: String, serverId: String) async throws
    func markSyncFailed(localId: String, error: String) async throws
    func markSyncSuccess(localId: String) async throws
    func incrementRetryCount(localId: String) async throws
    func resetStuckSyncingGroups() async throws

    // Member Operations (Local Only)
    func addMember(_ member: GroupMember, to groupId: String) async throws
    func removeMember(userId: String, from groupId: String) async throws
    func deactivateMember(userId: String, from groupId: String) async throws
    func updateMember(_ member: GroupMember, in groupId: String) async throws

    // Member Operations with Sync
    func addMemberWithSync(_ member: GroupMember, to groupId: String, ownerId: String) async throws
    func removeMemberWithSync(userId: String, from groupId: String, ownerId: String) async throws
    func updateMemberRoleWithSync(_ member: GroupMember, in groupId: String, ownerId: String) async throws
    func leaveGroupWithSync(groupId: String, userId: String) async throws
    func updateGroupWithSync(_ group: GroupChat) async throws

    // Settings Operations
    func updateSettings(_ settings: GroupSettings, for groupId: String) async throws

    // Join request operations
    func fetchPendingJoinRequests(groupId: String) async throws -> [GroupJoinRequest]
    func syncJoinRequests(groupId: String) async throws -> [GroupJoinRequest]
    func ingestJoinRequest(_ request: GroupJoinRequest, groupId: String) async throws
    func reconcileJoinRequestsFromStore(groupId: String) async throws -> [GroupJoinRequest]
    func approveJoinRequest(requestId: String, groupId: String, ownerId: String) async throws
    func declineJoinRequest(requestId: String, groupId: String, ownerId: String) async throws

    // Invite link operations
    func createInviteLink(groupId: String) async throws -> InviteDataDTO
}
