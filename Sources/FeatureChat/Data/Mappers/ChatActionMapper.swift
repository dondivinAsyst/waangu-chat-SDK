//
//  ChatActionMapper.swift
//  FeatureChat
//

import Foundation

protocol ChatActionMapperProtocol {
    func toGRDB(_ action: ChatActionItem) -> ChatActionModel
    func toDomain(_ grdb: ChatActionModel) -> ChatActionItem
}

final class ChatActionMapper: ChatActionMapperProtocol {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func toGRDB(_ action: ChatActionItem) -> ChatActionModel {
        var metadataJSON: String?
        if let metadata = action.metadata {
            metadataJSON = try? String(data: encoder.encode(metadata), encoding: .utf8)
        }

        return ChatActionModel(
            id: action.id,
            conversationId: action.conversationId,
            actionType: action.actionType.rawValue,
            targetId: action.targetId,
            performedBy: action.performedBy,
            metadataJSON: metadataJSON,
            timestamp: action.timestamp
        )
    }

    func toDomain(_ grdb: ChatActionModel) -> ChatActionItem {
        var metadata: [String: String]?
        if let metadataJSON = grdb.metadataJSON,
           let data = metadataJSON.data(using: .utf8) {
            metadata = try? decoder.decode([String: String].self, from: data)
        }

        return ChatActionItem(
            id: grdb.id,
            conversationId: grdb.conversationId,
            actionType: ChatActionType(rawValue: grdb.actionType) ?? .messageDeleted,
            performedBy: grdb.performedBy ?? "",
            targetId: grdb.targetId,
            metadata: metadata,
            timestamp: grdb.timestamp
        )
    }
}
