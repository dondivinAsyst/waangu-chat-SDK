//
//  CreateGroupDto.swift
//  AppModules
//
//  Created by Don divin on 5/28/26.
//


import Foundation

// MARK: - DTO

public struct CreateOrUpdateGroupRequest: Codable {
    
    // MARK: Properties
    
    let ownerId: String?
    let groupId: String?
    let name: String
    let description: String?
    let image: String?
    let memberUserIds: [String]?
    let settings : GroupSettings
    let message: String?  // ✅ Added to fix backend validation error
    
    // MARK: Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case ownerId
        case groupId  
        case name  
        case description
        case image
        case memberUserIds
        case settings
        case message
    }
    
    
    // MARK: Encoder
    
   public init(
        ownerId: String? = nil,
        groupId: String? = nil,
        name: String,
        description: String? = nil,
        image: String? = nil,
        memberUserIds: [String]? = nil,
        settings: GroupSettings,
        message: String? = nil  // ✅ Added to fix backend validation error
    ) {
        self.ownerId = ownerId
        self.groupId = groupId
        self.name = name
        self.description = description
        self.image = image
        self.memberUserIds = memberUserIds
        self.settings = settings
        self.message = message
    }
}

public struct AddGroupMemberRoleRequest: Codable {
    
    let ownerId: String
    let groupId: String
    let userId: String
    let role: GroupRole
    
    enum CodingKeys: String, CodingKey {
        case ownerId
        case groupId
        case userId
        case role
    }
}


public struct AddGroupMembersRequest: Codable {
    
    let ownerId: String
    let groupId: String
    let memberUserId: [String]
    
    enum CodingKeys: String, CodingKey {
        case ownerId
        case groupId
        case memberUserId
    }
}

/// POST /identity/groups/groups/leave
public struct LeaveGroupRequest: Codable {
    let groupId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case groupId
        case userId
    }
}

/// POST /identity/groups/groups/members/remove
public struct RemoveGroupMemberRequest: Codable {
    let groupId: String
    let userId: String
    let ownerId: String

    enum CodingKeys: String, CodingKey {
        case groupId
        case userId
        case ownerId
    }
}

public struct UpdateGroupRequest: Codable {
    let ownerId: String
    let groupId: String
    let name: String?
    let description: String?
    let image: String?
    let settings: GroupSettings?
    
    enum CodingKeys: String, CodingKey {
        case ownerId
        case groupId
        case name
        case description
        case image
        case settings
    }
    
    public init(
        ownerId: String,
        groupId: String,
        name: String? = nil,
        description: String? = nil,
        image: String? = nil,
        settings: GroupSettings? = nil
    ) {
        self.ownerId = ownerId
        self.groupId = groupId
        self.name = name
        self.description = description
        self.image = image
        self.settings = settings
    }
}
