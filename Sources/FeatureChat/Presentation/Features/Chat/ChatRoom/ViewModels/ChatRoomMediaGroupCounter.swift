//
//  ChatRoomMediaGroupCounter.swift
//  FeatureChat
//

import Foundation

enum ChatRoomMediaGroupCounter {

    static func count(groupId: String, in sections: [MessageSection]) -> Int {
        guard !groupId.isEmpty else { return 0 }

        for section in sections {
            for row in section.rows {
                if case .mediaGroup(_, let messages) = row,
                   messages.contains(where: { $0.groupId == groupId }) {
                    return messages.count
                }
            }
        }
        return 0
    }
}
