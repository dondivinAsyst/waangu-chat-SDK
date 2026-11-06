//
//  ContactsManager.swift
//  FeatureChat
//
//  Created by Refactoring on 5/5/26.
//

import Foundation
import Contacts
import WaanguCoreKit

// MARK: - Contacts Manager Protocol

public protocol ContactsManagerProtocol {
    func getContacts() async -> [FormattedContact]
    func requestAccess() async throws -> Bool
}

// MARK: - Contacts Manager Implementation

public final class ContactsManager: ContactsManagerProtocol {
    
    private let store = CNContactStore()
    
    public init() {}
    
    public func requestAccess() async throws -> Bool {
        return try await store.requestAccess(for: .contacts)
    }
    
    public func getContacts() async -> [FormattedContact] {
        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactImageDataKey,
            CNContactImageDataAvailableKey
        ] as [CNKeyDescriptor]
        
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [FormattedContact] = []
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let formattedContact = FormattedContact(from: contact)
                contacts.append(formattedContact)
            }
        } catch {
            debugLog("Failed to fetch contacts: \(error)")
        }
        
        return contacts
    }
}
