//
//  GroupJoinRequestResponseDto.swift
//  FeatureChat
//

import Foundation

public struct GroupJoinRequestListAPIResponse: Codable {
    let message: String?
    let status: Int?
    let data: [GroupJoinRequestDto]?
}

public struct GroupJoinRequestDto: Codable {
    let id: String
    let groupId: String
    let userId: String
    let userName: String?
    let userPhone: String?
    let userAvatar: String?
    let requestedAt: Date?

    func toDomain(fallbackGroupId: String) -> GroupJoinRequest {
        GroupJoinRequest(
            id: id,
            groupId: groupId.isEmpty ? fallbackGroupId : groupId,
            userId: userId,
            name: userName ?? "Unknown",
            phone: userPhone,
            avatar: userAvatar,
            requestedAt: requestedAt ?? Date()
        )
    }
}
