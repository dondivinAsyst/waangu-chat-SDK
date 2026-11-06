public protocol ContactsRepositoryProtocol {
    func fetchAndUpdateContacts() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])
    func fetchAndUpdateContactsIncremental() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])
    func fetchDevicesContacts() async throws -> [UserContactProps]
    func fetchContacts() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])
    func isContactPersisted(phone: String) async throws -> Bool
    func toggleBlockContact(contactId: String, blocked: Bool) async throws -> Bool
    func updateContactBlockStatus(contactId: String, isBlocked: Bool) async throws
}
