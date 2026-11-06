import Foundation

class GetContactsUseCase:GetContactsUseCaseProtocol {
    func execute() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])? {
        return try await repository.fetchAndUpdateContacts()
    }
    
    private let repository: ContactsRepositoryProtocol
    
    init(repository: ContactsRepositoryProtocol) {
        self.repository = repository
    }
}

class GetContactsIncrementalUseCase: GetContactsIncrementalUseCaseProtocol {
    private let repository: ContactsRepositoryProtocol
    
    init(repository: ContactsRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws -> (waanguContacts: [WaanguContact], UserContactProps: [UserContactProps])? {
        return try await repository.fetchAndUpdateContactsIncremental()
    }
}

class GetPersitedContactsUseCase:GetPersistedContactsUseCaseProtocol {
    func execute() async throws -> (waanguContacts:[WaanguContact],UserContactProps: [UserContactProps])? {
        try await repository.fetchContacts()
    }
    
    private let repository: ContactsRepositoryProtocol
    
    init(repository: ContactsRepositoryProtocol) {
        self.repository = repository
    }
}
class GetDeviceContactsUseCase:GetDeviceContactsUseCaseProtocol {
    func execute() async throws ->  [UserContactProps]? {
        return try await repository.fetchDevicesContacts()
    }
    
    private let repository: ContactsRepositoryProtocol
    
    init(repository: ContactsRepositoryProtocol) {
        self.repository = repository
    }
}

class IsContactPersistedUseCase: IsContactPersistedUseCaseProtocol {
    private let repository: ContactsRepositoryProtocol
    init(repository: ContactsRepositoryProtocol) {
        self.repository = repository
    }
    func execute(phone: String) async throws -> Bool {
        try await repository.isContactPersisted(phone: phone)
    }
}

class ToggleBlockContactUseCase: ToggleBlockContactUseCaseProtocol {
    private let repository: ContactsRepositoryProtocol
    
    init(repository: ContactsRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(contactId: String, blocked: Bool) async throws -> Bool {
        return try await repository.toggleBlockContact(contactId: contactId, blocked: blocked)
    }
}

class ContactsUseCases: ContactsUseCasesProtocol {
    var getUpdatedContacts: GetContactsUseCaseProtocol
    var getUpdatedContactsIncremental: GetContactsIncrementalUseCaseProtocol
    var getDeviceContacts: GetDeviceContactsUseCaseProtocol
    var getPersistedContacts: GetPersistedContactsUseCaseProtocol
    var isContactPersisted: IsContactPersistedUseCaseProtocol
    var toggleBlockContact: ToggleBlockContactUseCaseProtocol

    init(repository: ContactsRepositoryProtocol) {
        self.getUpdatedContacts = GetContactsUseCase(repository: repository)
        self.getUpdatedContactsIncremental = GetContactsIncrementalUseCase(repository: repository)
        self.getDeviceContacts = GetDeviceContactsUseCase(repository: repository)
        self.getPersistedContacts = GetPersitedContactsUseCase(repository: repository)
        self.isContactPersisted = IsContactPersistedUseCase(repository: repository)
        self.toggleBlockContact = ToggleBlockContactUseCase(repository: repository)
    }
}


//class GetContactsUseCase:GetContactsUseCaseProtocol {
//    func execute() throws -> [WaanguContact]? {
//        return try repository.fetchContacts()
//    }
//    
//    private let repository: ContactsRepositoryProtocol
//    
//    init(repository: ContactsRepositoryProtocol) {
//        self.repository = repository
//    }
//}
