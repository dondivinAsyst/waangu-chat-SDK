//
//  ChatRoomMessageSearchCoordinator.swift
//  FeatureChat
//

import Foundation

/// In-thread message text search.
enum ChatRoomMessageSearchCoordinator {

    static func matching(_ query: String, in messages: [MessageDataItem]) -> [MessageDataItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        return messages
            .filter { $0.message.text.lowercased().contains(normalized) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
