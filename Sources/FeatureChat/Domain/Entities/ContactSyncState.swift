import Foundation

public struct ContactSyncState {
    let contactId: String
    let rawPhone: String
    let normalizedPhone: String
    let contactHash: String
    let lastSyncedAt: Date
    
    public init(
        contactId: String,
        rawPhone: String,
        normalizedPhone: String,
        contactHash: String,
        lastSyncedAt: Date
    ) {
        self.contactId = contactId
        self.rawPhone = rawPhone
        self.normalizedPhone = normalizedPhone
        self.contactHash = contactHash
        self.lastSyncedAt = lastSyncedAt
    }
}
