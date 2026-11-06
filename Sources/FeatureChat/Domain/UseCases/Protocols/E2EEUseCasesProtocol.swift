import Foundation
import WaanguCoreKit

public protocol EncryptMessageUseCaseProtocol {
    func execute(text: String, conversationId: String) async throws -> String
}

public protocol DecryptMessageUseCaseProtocol {
    func execute(encryptedText: String, conversationId: String) async throws -> String
}

public protocol HasE2EESessionUseCaseProtocol {
    func execute(conversationId: String) async throws -> Bool
}

public protocol GenerateKeyBundleUseCaseProtocol {
    func execute() async throws -> PublicKeyBundle
}

public protocol InitiateE2EESessionUseCaseProtocol {
    func execute(conversationId: String, theirBundle: PublicKeyBundle) async throws -> Data
}

public protocol AcceptE2EESessionUseCaseProtocol {
    func execute(
        conversationId: String,
        theirIdentityKey: Data,
        theirEphemeralKey: Data,
        oneTimePreKeyId: Int?
    ) async throws
}

public protocol FetchKeyBundleUseCaseProtocol {
    func execute(userId: String) async throws -> PublicKeyBundle
}

public protocol UploadKeyBundleUseCaseProtocol {
    func execute() async throws
}

public protocol E2EEUseCasesProtocol {
    var encrypt: EncryptMessageUseCaseProtocol { get }
    var decrypt: DecryptMessageUseCaseProtocol { get }
    var hasSession: HasE2EESessionUseCaseProtocol { get }
    var generateKeyBundle: GenerateKeyBundleUseCaseProtocol { get }
    var initiateSession: InitiateE2EESessionUseCaseProtocol { get }
    var acceptSession: AcceptE2EESessionUseCaseProtocol { get }
    var fetchKeyBundle: FetchKeyBundleUseCaseProtocol { get }
    var uploadKeyBundle: UploadKeyBundleUseCaseProtocol { get }
}
