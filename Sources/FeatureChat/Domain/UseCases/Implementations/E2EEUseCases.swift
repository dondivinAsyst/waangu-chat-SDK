import Foundation
import WaanguCoreKit

class EncryptMessageUseCase: EncryptMessageUseCaseProtocol {

    private let service: any E2EEServiceProtocol

    init(service: any E2EEServiceProtocol) {
        self.service = service
    }

    func execute(text: String, conversationId: String) async throws -> String {
        return try await service.encrypt(text, conversationId: conversationId)
    }
}

class DecryptMessageUseCase: DecryptMessageUseCaseProtocol {

    private let service: any E2EEServiceProtocol

    init(service: any E2EEServiceProtocol) {
        self.service = service
    }

    func execute(encryptedText: String, conversationId: String) async throws -> String {
        return try await service.decrypt(encryptedText, conversationId: conversationId)
    }
}

class HasE2EESessionUseCase: HasE2EESessionUseCaseProtocol {

    private let service: any E2EEServiceProtocol

    init(service: any E2EEServiceProtocol) {
        self.service = service
    }

    func execute(conversationId: String) async throws -> Bool {
        return try await service.hasSession(for: conversationId)
    }
}

class GenerateKeyBundleUseCase: GenerateKeyBundleUseCaseProtocol {

    private let service: any E2EEServiceProtocol

    init(service: any E2EEServiceProtocol) {
        self.service = service
    }

    func execute() async throws -> PublicKeyBundle {
        let userId = CurrentSessionInfo.shared.currentUid
        return try await service.generateKeyBundle(userId: userId)
    }
}

class InitiateE2EESessionUseCase: InitiateE2EESessionUseCaseProtocol {

    private let service: any E2EEServiceProtocol

    init(service: any E2EEServiceProtocol) {
        self.service = service
    }

    func execute(conversationId: String, theirBundle: PublicKeyBundle) async throws -> Data {
        return try await service.initiateSession(conversationId: conversationId, theirBundle: theirBundle)
    }
}

class AcceptE2EESessionUseCase: AcceptE2EESessionUseCaseProtocol {

    private let service: any E2EEServiceProtocol

    init(service: any E2EEServiceProtocol) {
        self.service = service
    }

    func execute(
        conversationId: String,
        theirIdentityKey: Data,
        theirEphemeralKey: Data,
        oneTimePreKeyId: Int?
    ) async throws {
        try await service.acceptSession(
            conversationId: conversationId,
            theirIdentityKey: theirIdentityKey,
            theirEphemeralKey: theirEphemeralKey,
            oneTimePreKeyId: oneTimePreKeyId
        )
    }
}

class FetchKeyBundleUseCase: FetchKeyBundleUseCaseProtocol {

    private let repository: E2EERepositoryProtocol

    init(repository: E2EERepositoryProtocol) {
        self.repository = repository
    }

    func execute(userId: String) async throws -> PublicKeyBundle {
        return try await repository.fetchKeyBundle(userId: userId)
    }
}

class UploadKeyBundleUseCase: UploadKeyBundleUseCaseProtocol {

    private let service: any E2EEServiceProtocol
    private let repository: E2EERepositoryProtocol

    init(service: any E2EEServiceProtocol, repository: E2EERepositoryProtocol) {
        self.service = service
        self.repository = repository
    }

    /// Generates the local key bundle and uploads the public part to the server.
    func execute() async throws {
        let userId = CurrentSessionInfo.shared.currentUid
        let bundle = try await service.generateKeyBundle(userId: userId)
        try await repository.uploadKeyBundle(bundle)
    }
}

class E2EEUseCases: E2EEUseCasesProtocol {
    let encrypt: EncryptMessageUseCaseProtocol
    let decrypt: DecryptMessageUseCaseProtocol
    let hasSession: HasE2EESessionUseCaseProtocol
    let generateKeyBundle: GenerateKeyBundleUseCaseProtocol
    let initiateSession: InitiateE2EESessionUseCaseProtocol
    let acceptSession: AcceptE2EESessionUseCaseProtocol
    let fetchKeyBundle: FetchKeyBundleUseCaseProtocol
    let uploadKeyBundle: UploadKeyBundleUseCaseProtocol

    init(service: any E2EEServiceProtocol, repository: E2EERepositoryProtocol) {
        self.encrypt = EncryptMessageUseCase(service: service)
        self.decrypt = DecryptMessageUseCase(service: service)
        self.hasSession = HasE2EESessionUseCase(service: service)
        self.generateKeyBundle = GenerateKeyBundleUseCase(service: service)
        self.initiateSession = InitiateE2EESessionUseCase(service: service)
        self.acceptSession = AcceptE2EESessionUseCase(service: service)
        self.fetchKeyBundle = FetchKeyBundleUseCase(repository: repository)
        self.uploadKeyBundle = UploadKeyBundleUseCase(service: service, repository: repository)
    }
}
