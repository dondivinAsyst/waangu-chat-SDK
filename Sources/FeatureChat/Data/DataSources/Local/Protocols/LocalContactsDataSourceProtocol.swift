import Foundation

protocol LocalContactsDataSourceProtocol {
    func fetchContacts() async throws -> [WaanguContact]
    func saveContact(_ contact: WaanguContact) async throws
    func deleteAllContacts() async throws
    func isContactPersisted(phone: String) async throws -> Bool
    func updateContactBlockStatus(contactId: String, isBlocked: Bool) async throws
    func replaceAllContacts(_ contacts: [WaanguContact]) async throws
    func updateContactsIncremental(toAddOrUpdate: [WaanguContact], toDeleteIds: [String]) async throws
}
