//
//  GroupPermissionsMapper.swift
//  FeatureChat
//

import Foundation

struct GroupPermissionsMapper {

    static func toDomain(_ model: GroupPermissionsModel) -> GroupPermissions {
        GroupPermissions(
            sendMessages: model.sendMessages,
            addMembers: model.addMembers,
            inviteLink: model.inviteLink,
            changeGroupInfo: model.changeGroupInfo,
            approveNewMembers: model.approveNewMembers,
            onlyAdminsCanPost: model.onlyAdminsCanPost,
            sendMessagesHistory: model.sendMessagesHistory
        )
    }

    static func toModel(_ permissions: GroupPermissions, groupLocalId: String, groupServerId: String?) -> GroupPermissionsModel {
        GroupPermissionsModel(
            id: groupLocalId,
            groupLocalId: groupLocalId,
            groupServerId: groupServerId,
            sendMessages: permissions.sendMessages,
            addMembers: permissions.addMembers,
            inviteLink: permissions.inviteLink,
            changeGroupInfo: permissions.changeGroupInfo,
            approveNewMembers: permissions.approveNewMembers,
            onlyAdminsCanPost: permissions.onlyAdminsCanPost,
            sendMessagesHistory: permissions.sendMessagesHistory,
            updatedAt: Date()
        )
    }

    static func toRequest(groupServerId: String, permissions: GroupPermissions) -> UpdateGroupPermissionsRequest {
        UpdateGroupPermissionsRequest(
            groupId: groupServerId,
            permissions: GroupPermissionsPayload(
                sendMessages: permissions.sendMessages,
                addMembers: permissions.addMembers,
                inviteLink: permissions.inviteLink,
                changeGroupInfo: permissions.changeGroupInfo,
                approveNewMembers: permissions.approveNewMembers,
                onlyAdminsCanPost: permissions.onlyAdminsCanPost,
                sendMessagesHistory: permissions.sendMessagesHistory
            )
        )
    }
}
