import Foundation
import WaanguCoreKit

final class HTTPGroupDataSource: RemoteGroupDataSourceProtocol {
    private let httpClient: APIClientProtocol
    
    init(httpClient: APIClientProtocol) {
        self.httpClient = httpClient
    }
    
    // MARK: - Group Operations
    
    func createGroup(_ request: CreateOrUpdateGroupRequest) async throws -> GroupResponseDto {
        let endpoint = GroupEndpoints.create(request)
        let response: GroupAPIResponse = try await httpClient.request(endpoint: endpoint)
        return response.data
    }
    
    func getGroup(id: String) async throws -> GroupResponseDto {
        let endpoint = GroupEndpoints.get(id)
        let response: GroupAPIResponse = try await httpClient.request(endpoint: endpoint)
        return response.data
    }
    
    func updateGroup(_ request: UpdateGroupRequest) async throws -> GroupResponseDto {
        let endpoint = GroupEndpoints.update(request)
        let response: GroupAPIResponse = try await httpClient.request(endpoint: endpoint)
        return response.data
    }
    
    // MARK: - Member Operations
    
    func addMembers(_ request: AddGroupMembersRequest) async throws {
        let endpoint = GroupEndpoints.addMember(request)
        let _: EmptyResponse = try await httpClient.request(endpoint: endpoint)
    }
    
    func removeMembers(_ request: RemoveGroupMemberRequest) async throws {
        let endpoint = GroupEndpoints.removeMember(request)
        let _: EmptyResponse = try await httpClient.request(endpoint: endpoint)
    }
    
    func leaveGroup(_ request: LeaveGroupRequest) async throws {
        let endpoint = GroupEndpoints.memberLeave(request)
        let _: EmptyResponse = try await httpClient.request(endpoint: endpoint)
    }
    
    func updateMemberRole(_ request: AddGroupMemberRoleRequest) async throws {
       
        let endpoint = GroupEndpoints.addMemberRole(request)
      debugLog("this was an endpoint call for updating a member role in a group \(endpoint)")
        let res:APIResponse = try await httpClient.request(endpoint: endpoint)
        debugLog("this was an the response from the api call \(res)")
    }

    // MARK: - Join Requests

    func fetchJoinRequests(groupId: String) async throws -> [GroupJoinRequestDto] {
        debugLog("this was called for fetching join requests")
        #if DEBUG
        print("this was called for fetching join requests test mode only")
        if JoinRequestDebugConfiguration.useMockJoinRequestAPI {
            return JoinRequestDebugMockStore.fetch(groupId: groupId)
        }   
        #endif

        let endpoint = GroupEndpoints.listJoinRequests(groupId: groupId)
        let response: GroupJoinRequestListAPIResponse = try await httpClient.request(endpoint: endpoint)
        return response.data ?? []
    }

    func approveJoinRequest(_ request: ApproveJoinRequestBody) async throws {
        #if DEBUG
        if JoinRequestDebugConfiguration.useMockJoinRequestAPI {
            JoinRequestDebugMockStore.remove(groupId: request.groupId, requestId: request.requestId)
            return
        }
        #endif

        let endpoint = GroupEndpoints.approveJoinRequest(request)
        let _: EmptyResponse = try await httpClient.request(endpoint: endpoint)
    }

    func declineJoinRequest(_ request: DeclineJoinRequestBody) async throws {
        #if DEBUG
        if JoinRequestDebugConfiguration.useMockJoinRequestAPI {
            JoinRequestDebugMockStore.remove(groupId: request.groupId, requestId: request.requestId)
            return
        }
        #endif

        let endpoint = GroupEndpoints.declineJoinRequest(request)
        let _: EmptyResponse = try await httpClient.request(endpoint: endpoint)
    }

    // MARK: - Invite Link Operations

    func createInviteLink(groupId: String) async throws -> InviteResponseDTO {
        let endpoint = GroupEndpoints.createInviteGroupLink(groupId: groupId)
        let response: InviteResponseDTO = try await httpClient.request(endpoint: endpoint)
        return response
    }
}

struct EmptyResponse: Codable {}
