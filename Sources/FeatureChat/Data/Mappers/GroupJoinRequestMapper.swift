//
//  GroupJoinRequestMapper.swift
//  FeatureChat
//

import Foundation

protocol GroupJoinRequestMapperProtocol {
    func toGRDB(_ request: GroupJoinRequest, groupLocalId: String) -> GroupJoinRequestModel
    func toDomain(_ model: GroupJoinRequestModel) -> GroupJoinRequest
}

struct GroupJoinRequestMapper: GroupJoinRequestMapperProtocol {
    func toGRDB(_ request: GroupJoinRequest, groupLocalId: String) -> GroupJoinRequestModel {
        GroupJoinRequestModel(
            id: request.id,
            groupLocalId: groupLocalId,
            userId: request.userId,
            name: request.name,
            phone: request.phone,
            avatar: request.avatar,
            requestedAt: request.requestedAt
        )
    }

    func toDomain(_ model: GroupJoinRequestModel) -> GroupJoinRequest {
        GroupJoinRequest(
            id: model.id,
            groupId: model.groupLocalId,
            userId: model.userId,
            name: model.name,
            phone: model.phone,
            avatar: model.avatar,
            requestedAt: model.requestedAt
        )
    }
}
