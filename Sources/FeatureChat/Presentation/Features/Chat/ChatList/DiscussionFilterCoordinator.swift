//
//  DiscussionFilterCoordinator.swift
//  FeatureChat
//

import Foundation

enum DiscussionFilterCoordinator {

    static func apply(
        _ filter: DiscussionFilter,
        to discussions: [DiscussionChatItem],
        customLists: [DiscussionCustomList]
    ) -> [DiscussionChatItem] {
        switch filter {
        case .all:
            return discussions
        case .unread:
            return discussions.filter(isUnread)
        case .favorites:
            return discussions.filter { $0.setting?.isMyFavority == true }
        case .groups:
            return discussions.filter { $0.contact?.isGroup == true }
        case .customList(let listId, _):
            guard let list = customLists.first(where: { $0.id == listId }) else { return [] }
            let ids = Set(list.conversationIds)
            return discussions.filter { ids.contains($0.conversationId) }
        }
    }

    static func isUnread(_ discussion: DiscussionChatItem) -> Bool {
        discussion.count > 0
    }

    static func builtInFilters() -> [DiscussionFilter] {
        [.all, .unread, .favorites, .groups]
    }

    static func allFilters(customLists: [DiscussionCustomList]) -> [DiscussionFilter] {
        builtInFilters() + customLists.map { .customList(id: $0.id, name: $0.name) }
    }

    static func count(
        for filter: DiscussionFilter,
        in discussions: [DiscussionChatItem],
        customLists: [DiscussionCustomList]
    ) -> Int {
        apply(filter, to: discussions, customLists: customLists).count
    }

    static func filterItems(
        discussions: [DiscussionChatItem],
        customLists: [DiscussionCustomList]
    ) -> [DiscussionFilterItem] {
        allFilters(customLists: customLists).map { filter in
            DiscussionFilterItem(
                filter: filter,
                count: count(for: filter, in: discussions, customLists: customLists)
            )
        }
    }
}
