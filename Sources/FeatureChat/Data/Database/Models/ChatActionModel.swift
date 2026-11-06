//
//  ChatActionModel.swift
//  FeatureChat
//
//  Created by Kiro on 6/1/26.
//

import Foundation
import WaanguCoreKit

/// GRDB model for chat actions (delete, edit, reply, forward, etc.)
public struct ChatActionModel: Storable {
    public let id: String
    public let conversationId: String
    public let actionType: String
    public let targetId: String?
    public let performedBy: String?
    public let metadataJSON: String?
    public let timestamp: Date
    
    // MARK: - Storable Protocol
    public static let namespace = "chat"
    public static let schemaVersion = 1
    
    /// Indexed fields for fast queries
    public static let indexedFields = [
        "conversation_id",
        "action_type",
        "target_id",
        "performed_by",
        "timestamp"
    ]
    
    /// No searchable fields for chat actions
    public static let searchableFields: [String] = []
    
    /// Foreign key to discussions
    public static let foreignKeys = [
        StorableForeignKey(
            "conversation_id",
            references: "chat_conversationmodels",
            onDelete: .cascade
        )
    ]
    
    // MARK: - CodingKeys for snake_case column mapping
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case actionType = "action_type"
        case targetId = "target_id"
        case performedBy = "performed_by"
        case metadataJSON = "metadata_json"
        case timestamp
    }
    
    // MARK: - Initializer
    public init(
        id: String,
        conversationId: String,
        actionType: String,
        targetId: String? = nil,
        performedBy: String? = nil,
        metadataJSON: String? = nil,
        timestamp: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.actionType = actionType
        self.targetId = targetId
        self.performedBy = performedBy
        self.metadataJSON = metadataJSON
        self.timestamp = timestamp
    }
}
