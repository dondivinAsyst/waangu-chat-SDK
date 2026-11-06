import Foundation
import WaanguCoreKit
import WaanguNetworkKit


enum GroupEndpoints {
    case create(CreateOrUpdateGroupRequest)
    case get(String)
    case update(UpdateGroupRequest)
    case addMember(AddGroupMembersRequest)
    case addMemberRole(AddGroupMemberRoleRequest)
    case removeMember(RemoveGroupMemberRequest)
    case memberLeave(LeaveGroupRequest)
    case createInviteGroupLink(groupId:String)
    case listJoinRequests(groupId: String)
    case approveJoinRequest(ApproveJoinRequestBody)
    case declineJoinRequest(DeclineJoinRequestBody)
    case updatePermissions(UpdateGroupPermissionsRequest)
}

extension GroupEndpoints: APIEndpoint {
 
    
    var path: String {
        switch self {
        case .create:
            return "/identity/groups"
        case .get(let groupId):
            return "/identity/groups/\(groupId)"
        case .update:
            return "identity/groups"
        case .addMember:
            return "/identity/groups/members/add"
        case .removeMember:
            return "/identity/groups/members/remove"
        case .addMemberRole:
            return "/identity/groups/members/role"
        case .memberLeave:
            return "/identity/groups/leave"
        case .createInviteGroupLink(let groupId):
            return "/identity/groups/\(groupId)/invite-link"
        case .listJoinRequests(let groupId):
            return "/identity/groups/\(groupId)/join-requests"
        case .approveJoinRequest:
            return "/identity/groups/join-requests/approve"
        case .declineJoinRequest:
            return "/identity/groups/join-requests/decline"
        case .updatePermissions:
            return "/identity/groups/settings"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .create, .addMember, .removeMember, .addMemberRole, .memberLeave,
                .approveJoinRequest, .declineJoinRequest, .createInviteGroupLink:
            return .post
        case .get, .listJoinRequests:
            return .get
        case .update, .updatePermissions:
            return .put
            
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .create(let request):
            return try? request.toDictionary()
        case .update(let request):
            return try? request.toDictionary()
        case .addMember(let req):
            return try? req.toDictionary()
        case .addMemberRole(let req):
        
            return try? req.toDictionary()
        case .memberLeave(let req):
            return try? req.toDictionary()
        case .createInviteGroupLink:
            return nil
        case .removeMember(let req):
            return try? req.toDictionary()
        case .approveJoinRequest(let req):
            return try? req.toDictionary()
        case .declineJoinRequest(let req):
            return try? req.toDictionary()
        case .updatePermissions(let req):
            return try? req.toDictionary()
        case .get, .listJoinRequests:
            return nil
        }
    }
    
    var headers: [String: String]? {
        return [
            "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-chat-session": CurrentSessionInfo.shared.sessionId
        ]
    }
}

extension GroupEndpoints: EndpointPolicyProviding {
    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var isIdempotent: Bool {
        switch self {
        case .get:
            return true
        case .create, .update, .addMember, .removeMember, .addMemberRole, .memberLeave,
                .approveJoinRequest, .declineJoinRequest, .updatePermissions,.createInviteGroupLink:
            return false
        case .listJoinRequests:
            return true
        }
    }

    var rateLimitPolicy: RateLimitPolicy { .standard }
}


