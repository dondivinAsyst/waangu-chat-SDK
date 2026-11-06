//
//  ContactSyncStateModel.swift
//  FeatureChat
//
//  Created by Kiro on 6/1/26.
//

import Foundation
import WaanguCoreKit

/// GRDB model for contact synchronization state tracking
public struct ContactSyncStateModel: Storable {
    public let id: String
    public let contactId: String?
    public let rawPhone: String?
    public let normalizedPhone: String?
    public let contactHash: String?
    public let lastSyncedAt: Date?
    
    // MARK: - Storable Protocol
    public static let namespace = "chat"
    public static let schemaVersion = 1
    
    /// Indexed fields for fast queries
    public static let indexedFields = [
        "contact_id",
        "normalized_phone",
        "contact_hash",
        "last_synced_at"
    ]
    
    /// No searchable fields for sync state
    public static let searchableFields: [String] = []
    
    /// No foreign keys — `contactId` is the device address-book identifier,
    /// not a row id in `chat_contactmodels` (server/Waangu contacts).
    public static let foreignKeys: [StorableForeignKey] = []
    
    // MARK: - CodingKeys for snake_case column mapping
    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "contact_id"
        case rawPhone = "raw_phone"
        case normalizedPhone = "normalized_phone"
        case contactHash = "contact_hash"
        case lastSyncedAt = "last_synced_at"
    }
    
    // MARK: - Initializer
    public init(
        id: String,
        contactId: String? = nil,
        rawPhone: String? = nil,
        normalizedPhone: String? = nil,
        contactHash: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.contactId = contactId
        self.rawPhone = rawPhone
        self.normalizedPhone = normalizedPhone
        self.contactHash = contactHash
        self.lastSyncedAt = lastSyncedAt
    }
}
