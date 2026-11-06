import Foundation
import WaanguCoreKit

final class E2EERepository: E2EERepositoryProtocol {

    private let httpDataSource: HTTPE2EEDataSourceProtocol

    init(httpDataSource: HTTPE2EEDataSourceProtocol) {
        self.httpDataSource = httpDataSource
    }

    func uploadKeyBundle(_ bundle: PublicKeyBundle) async throws {
        let request = E2EEKeyRegistrationRequest(
            userId: bundle.userId,
            identityKey: bundle.identityKey.base64EncodedString(),
            signedPreKey: bundle.signedPreKey.base64EncodedString(),
            signedPreKeySignature: bundle.signedPreKeySignature.base64EncodedString(),
            oneTimePreKeys: bundle.oneTimePreKeys.map { $0.base64EncodedString() }
        )
        try await httpDataSource.registerKeys(request)
    }

    func fetchKeyBundle(userId: String) async throws -> PublicKeyBundle {
        let response = try await httpDataSource.fetchKeyBundle(userId: userId)
        guard let bundle = response.toPublicKeyBundle() else {
            throw E2EEError.invalidPublicKey
        }
        return bundle
    }
}
