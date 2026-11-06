//
//  ChatRoomGroupMembersCoordinator.swift
//  FeatureChat
//

import Foundation

/// Adds new members to an existing group chat.
enum ChatRoomGroupMembersCoordinator {

    static func newMembers(
        from contacts: [UserContactProps],
        existing: [GroupMember]
    ) -> [GroupMember] {
        contacts.compactMap { contact in
            let alreadyExists = existing.contains { $0.userId == contact.userId }
            guard !alreadyExists else { return nil }
            return GroupMember(
                userId: contact.userId,
                name: contact.name,
                phone: contact.phone,
                avatar: contact.avatar,
                role: .MEMBER
            )
        }
    }

    static func addMembers(
        _ members: [GroupMember],
        to group: GroupChat,
        using groupUseCases: GroupUseCasesProtocol
    ) async throws {
        for member in members {
            try await groupUseCases.addMember.execute(
                member: member,
                to: group.id,
                ownerId: group.createdBy
            )
        }
    }
}
