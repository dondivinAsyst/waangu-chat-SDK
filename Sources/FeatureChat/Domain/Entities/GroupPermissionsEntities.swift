//
//  GroupPermissionsEntities.swift
//  FeatureChat
//

import Foundation

public struct GroupPermissions: Codable, Equatable {
    public var sendMessages: Bool
    public var addMembers: Bool
    public var inviteLink: Bool
    public var changeGroupInfo: Bool
    public var approveNewMembers: Bool
    public var onlyAdminsCanPost: Bool
    public var sendMessagesHistory: Bool

    public init(
        sendMessages: Bool = true,
        addMembers: Bool = true,
        inviteLink: Bool = true,
        changeGroupInfo: Bool = false,
        approveNewMembers: Bool = false,
        onlyAdminsCanPost: Bool = false,
        sendMessagesHistory: Bool = true
    ) {
        self.sendMessages = sendMessages
        self.addMembers = addMembers
        self.inviteLink = inviteLink
        self.changeGroupInfo = changeGroupInfo
        self.approveNewMembers = approveNewMembers
        self.onlyAdminsCanPost = onlyAdminsCanPost
        self.sendMessagesHistory = sendMessagesHistory
    }
}
