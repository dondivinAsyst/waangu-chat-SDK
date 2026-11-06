//
//  GRDBContactsDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class GRDBContactsDataSource: LocalContactsDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol
    private let mapper: ContactsMappersProtocol

    init(
        store: any DatabaseRepositoryProtocol,
        mapper: ContactsMappersProtocol
    ) {
        self.store = store
        self.mapper = mapper
    }

    // MARK: - Fetch

    func fetchContacts() async throws -> [WaanguContact] {
        let query = QuerySpec(
            filter: FilterSpec("is_registered == %@", AnyStorableArgument.bool(true))
        )
        let models = try await store.fetch(ContactModel.self, query: query)
        return models.map { mapper.toDomain($0) }
    }

    // MARK: - Save

    func saveContact(_ contact: WaanguContact) async throws {
        let existing = try await store.fetchOne(ContactModel.self, id: contact.id)
        if existing == nil {
            let model = mapper.toGRDB(contact)
            try await store.save(model)
        }
    }

    // MARK: - Delete

    func deleteAllContacts() async throws {
        try await store.deleteAll(ContactModel.self, query: nil)
    }

    // MARK: - Existence check

    func isContactPersisted(phone: String) async throws -> Bool {
        let query = QuerySpec(
            filter: FilterSpec("phone == %@", .string(phone)),
            limit: 1
        )
        let count = try await store.count(ContactModel.self, query: query)
        return count > 0
    }

    // MARK: - Block status

    func updateContactBlockStatus(contactId: String, isBlocked: Bool) async throws {
        guard let contact = try await store.fetchOne(ContactModel.self, id: contactId) else {
            throw NSError(
                domain: "ContactNotFound",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Contact with ID \(contactId) not found"]
            )
        }

        let updated = ContactModel(
            id: contact.id,
            userId: contact.userId,
            phone: contact.phone,
            name: contact.name,
            username: contact.username,
            avatarURL: contact.avatarURL,
            bio: contact.bio,
            lastSeenAt: contact.lastSeenAt,
            isRegistered: contact.isRegistered,
            isVerified: contact.isVerified,
            isBlocked: isBlocked,
            isFavorite: contact.isFavorite,
            isSavedContact: contact.isSavedContact,
            showLastSeen: contact.showLastSeen,
            showProfilePhoto: contact.showProfilePhoto,
            showStatus: contact.showStatus,
            createdAt: contact.createdAt,
            updatedAt: Date()
        )
        try await store.save(updated)
    }

    // MARK: - Replace all (full sync)

    func replaceAllContacts(_ contacts: [WaanguContact]) async throws {
        let query = QuerySpec(filter: FilterSpec("is_registered == %@", .bool(true)))
        let existing = try await store.fetch(ContactModel.self, query: query)

        let incomingIds   = Set(contacts.map(\.id))
        let incomingPhones = Set(contacts.map { $0.phone })

        for existingContact in existing {
            if !incomingIds.contains(existingContact.id),
               !incomingPhones.contains(existingContact.phone) {
                try await store.delete(ContactModel.self, id: existingContact.id)
            }
        }

        for contact in contacts {
            let model = mapper.toGRDB(contact)
            try await store.save(model)
        }
    }

    // MARK: - Incremental update

    func updateContactsIncremental(
        toAddOrUpdate: [WaanguContact],
        toDeleteIds: [String]
    ) async throws {
        for idStr in toDeleteIds {
            try await store.delete(ContactModel.self, id: idStr)
        }
        for contact in toAddOrUpdate {
            let model = mapper.toGRDB(contact)
            try await store.save(model)
        }
    }
}
