//
//  GroupChannelItemMapper.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

enum GroupChannelItemMapper {

    static func makeChannel(
        from result: CreateGroupWithDiscussionResult,
        translator: (any TranslationServiceProtocol)? = nil
    ) -> ChannelItem {
        let group = result.group
        let discussion = result.discussion
        let currentUid = CurrentSessionInfo.shared.currentUid

        let userItems: [UserItem] = group.members.map { member in
            UserItem(
                uid: member.userId,
                username: member.name,
                email: "",
                phoneNumber: member.phone,
                profileImageURL: member.avatar
            )
        }

        let adminUids = group.members
            .filter { $0.role == .ADMIN }
            .map(\.userId)

        let fallbackLastMessage: String = {
            if let t = translator {
                return discussion?.lastMessage.message.text
                    ?? t.resolve(
                        key: ChatTranslationKeys.GROUP_CREATED_YOU,
                        module: ChatTranslationKeys.MODULE
                    ).value
            }
            return discussion?.lastMessage.message.text ?? "You created the group"
        }()

        return ChannelItem(
            id: group.localId,
            name: group.name,
            lastMessage: fallbackLastMessage,
            creationDate: group.createdAt,
            lastMessageTimestamp: discussion?.lastMessage.createdAt ?? Date(),
            membersCount: group.members.count,
            adminUids: adminUids,
            memberUids: group.members.map(\.userId),
            members: userItems,
            thumbnailUrl: group.avatarUrl,
            createdBy: currentUid,
            lastMessageType: .text
        )
    }
}
