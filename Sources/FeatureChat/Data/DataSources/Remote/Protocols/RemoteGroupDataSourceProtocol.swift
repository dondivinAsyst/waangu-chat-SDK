import Foundation

public protocol RemoteGroupDataSourceProtocol {
    // CRUD Operations
    func createGroup(_ request: CreateOrUpdateGroupRequest) async throws -> GroupResponseDto
    func getGroup(id: String) async throws -> GroupResponseDto
    func updateGroup(_ request: UpdateGroupRequest) async throws -> GroupResponseDto
    
    // Member Operations
    func addMembers(_ request: AddGroupMembersRequest) async throws
    func removeMembers(_ request: RemoveGroupMemberRequest) async throws
    func leaveGroup(_ request: LeaveGroupRequest) async throws
    func updateMemberRole(_ request: AddGroupMemberRoleRequest) async throws

    // Join request operations
    func fetchJoinRequests(groupId: String) async throws -> [GroupJoinRequestDto]
    func approveJoinRequest(_ request: ApproveJoinRequestBody) async throws
    func declineJoinRequest(_ request: DeclineJoinRequestBody) async throws

    // Invite link operations
    func createInviteLink(groupId: String) async throws -> InviteResponseDTO
}

// MARK: - Response Models

//public struct CreateGroupResponse: Codable {
//    let groupId: String
//    let name: String
//    let createdAt: Date
//    let members: [GroupMemberResponse]
//}
//
//public struct GroupResponse: Codable {
//    let id: String
//    let name: String
//    let description: String?
//    let type: String
//    let members: [GroupMemberResponse]
//    let createdAt: Date
//    let updatedAt: Date
//}
//
//struct GroupMemberResponse: Codable {
//    let userId: String
//    let name: String
//    let phone: String
//    let avatar: String?
//    let role: String
//}


