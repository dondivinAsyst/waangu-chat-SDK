import Foundation
import WaanguCoreKit

protocol HTTPE2EEDataSourceProtocol {
    func registerKeys(_ request: E2EEKeyRegistrationRequest) async throws
    func fetchKeyBundle(userId: String) async throws -> E2EEKeyBundleResponse
}

final class HTTPE2EEDataSource: HTTPE2EEDataSourceProtocol {

    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    func registerKeys(_ request: E2EEKeyRegistrationRequest) async throws {
//        _ = try await apiClient.request(
//            E2EEEndpoints.registerKeys(request)
//        ) as EmptyResponse
    }

    func fetchKeyBundle(userId: String) async throws -> E2EEKeyBundleResponse {
        return try await apiClient.request(endpoint: 
            E2EEEndpoints.fetchKeyBundle(userId: userId)
        ) as E2EEKeyBundleResponse
    }
}

