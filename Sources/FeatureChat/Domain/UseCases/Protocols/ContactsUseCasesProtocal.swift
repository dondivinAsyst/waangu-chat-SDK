import Foundation

public protocol GetContactsUseCaseProtocol {
    func execute() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])?
}

public protocol GetContactsIncrementalUseCaseProtocol {
    func execute() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])?
}

public protocol GetPersistedContactsUseCaseProtocol {
    func execute() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])?
}
public protocol GetDeviceContactsUseCaseProtocol {
    func execute() async throws ->  [UserContactProps]?
}
public protocol IsContactPersistedUseCaseProtocol {
    func execute(phone: String) async throws -> Bool
}

public protocol ToggleBlockContactUseCaseProtocol {
    func execute(contactId: String, blocked: Bool) async throws -> Bool
}

public protocol ContactsUseCasesProtocol {
    var getUpdatedContacts: GetContactsUseCaseProtocol { get }
    var getUpdatedContactsIncremental: GetContactsIncrementalUseCaseProtocol { get }
    var getDeviceContacts: GetDeviceContactsUseCaseProtocol { get }
    var getPersistedContacts: GetPersistedContactsUseCaseProtocol { get }
    var isContactPersisted: IsContactPersistedUseCaseProtocol { get }
    var toggleBlockContact: ToggleBlockContactUseCaseProtocol { get }
}
