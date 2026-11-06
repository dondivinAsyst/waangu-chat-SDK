//
//  UpdateGroupPermissionsRequest.swift
//  FeatureChat
//

import Foundation

public struct UpdateGroupPermissionsRequest: Codable {
    let groupId: String
    let permissions: GroupPermissionsPayload

    enum CodingKeys: String, CodingKey {
        case groupId
        case permissions
    }
}

public struct GroupPermissionsPayload: Codable {
    let sendMessages: Bool
    let addMembers: Bool
    let inviteLink: Bool
    let changeGroupInfo: Bool
    let approveNewMembers: Bool
    let onlyAdminsCanPost: Bool
    let sendMessagesHistory: Bool

    enum CodingKeys: String, CodingKey {
        case sendMessages
        case addMembers
        case inviteLink
        case changeGroupInfo
        case approveNewMembers
        case onlyAdminsCanPost
        case sendMessagesHistory
    }
}
