//
//  GroupJoinRequestRequest.swift
//  FeatureChat
//

import Foundation

public struct ApproveJoinRequestBody: Codable {
    let groupId: String
    let requestId: String
    let ownerId: String

    enum CodingKeys: String, CodingKey {
        case groupId
        case requestId
        case ownerId
    }
}

public struct DeclineJoinRequestBody: Codable {
    let groupId: String
    let requestId: String
    let ownerId: String

    enum CodingKeys: String, CodingKey {
        case groupId
        case requestId
        case ownerId
    }
}
