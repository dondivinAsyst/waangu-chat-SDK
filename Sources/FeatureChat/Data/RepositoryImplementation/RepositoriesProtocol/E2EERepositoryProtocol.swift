import Foundation
import WaanguCoreKit

protocol E2EERepositoryProtocol {
    func uploadKeyBundle(_ bundle: PublicKeyBundle) async throws
    func fetchKeyBundle(userId: String) async throws -> PublicKeyBundle
}
