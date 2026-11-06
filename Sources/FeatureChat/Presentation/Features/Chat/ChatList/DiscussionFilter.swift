//
//  DiscussionFilter.swift
//  FeatureChat
//

import Foundation

/// Built-in and custom list filters for the chats inbox.
enum DiscussionFilter: Hashable, Identifiable {
    case all
    case unread
    case favorites
    case groups
    case customList(id: String, name: String)

    var id: String {
        switch self {
        case .all: return "all"
        case .unread: return "unread"
        case .favorites: return "favorites"
        case .groups: return "groups"
        case .customList(let id, _): return "list.\(id)"
        }
    }

    var title: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .favorites: return "Favorites"
        case .groups: return "Groups"
        case .customList(_, let name): return name
        }
    }

    /// Translation key for built-in filters; custom lists use the stored name.
    var translationKey: String? {
        switch self {
        case .all: return ChatTranslationKeys.FILTER_ALL
        case .unread: return ChatTranslationKeys.FILTER_UNREAD
        case .favorites: return ChatTranslationKeys.FILTER_FAVORITES
        case .groups: return ChatTranslationKeys.FILTER_GROUPS
        case .customList: return nil
        }
    }

    var isBuiltIn: Bool {
        switch self {
        case .customList: return false
        default: return true
        }
    }
}

struct DiscussionFilterItem: Identifiable, Equatable {
    let filter: DiscussionFilter
    let count: Int

    var id: String { filter.id }

    var title: String { filter.title }
}

struct DiscussionCustomList: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var conversationIds: [String]

    init(id: String = UUID().uuidString, name: String, conversationIds: [String] = []) {
        self.id = id
        self.name = name
        self.conversationIds = conversationIds
    }
}
