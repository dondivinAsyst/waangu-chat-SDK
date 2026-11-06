import Foundation

public struct ContactChanges {
    let added: [FormattedContact]
    let updated: [FormattedContact]
    let deleted: [String] // Contact IDs
    let unchanged: [FormattedContact]
    
    var hasChanges: Bool {
        return !added.isEmpty || !updated.isEmpty || !deleted.isEmpty
    }
    
    var totalChanges: Int {
        return added.count + updated.count + deleted.count
    }
}

public struct ContactChangeDetector {
    
    /// Detect changes between current device contacts and last sync state
    public static func detectChanges(
        currentContacts: [FormattedContact],
        lastSyncState: [ContactSyncState]
    ) -> ContactChanges {
        
        // Create lookup maps
        let currentContactsById = Dictionary(uniqueKeysWithValues: currentContacts.map { ($0.id, $0) })
        let lastSyncById = Dictionary(uniqueKeysWithValues: lastSyncState.map { ($0.contactId, $0) })
        
        var added: [FormattedContact] = []
        var updated: [FormattedContact] = []
        var unchanged: [FormattedContact] = []
        var deleted: [String] = []
        
        // Check current contacts
        for contact in currentContacts {
            if let syncState = lastSyncById[contact.id] {
                // Contact existed before, check if changed
                let currentHash = ContactHashGenerator.generateHash(for: contact)
                if currentHash != syncState.contactHash {
                    updated.append(contact)
                } else {
                    unchanged.append(contact)
                }
            } else {
                // New contact
                added.append(contact)
            }
        }
        
        // Check for deleted contacts
        for syncState in lastSyncState {
            if currentContactsById[syncState.contactId] == nil {
                deleted.append(syncState.contactId)
            }
        }
        
        return ContactChanges(
            added: added,
            updated: updated,
            deleted: deleted,
            unchanged: unchanged
        )
    }
}
