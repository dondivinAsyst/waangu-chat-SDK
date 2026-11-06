import Foundation
import WaanguCoreKit
import WaanguNetworkKit

protocol HTTPStatusDataSourceProtocol {
    func getContactStatus() async throws -> APIResponse
    func onPostStatus(_ request: CreateStatusRequest) async throws -> APIResponse
    func deleteStatus(_ request: DeleteStatusRequest) async throws -> APIResponse
    func syncStories(since: Date?, limit: Int) async throws -> StoriesSyncResponseDTO
}

class HTTPStatusDataSource: HTTPStatusDataSourceProtocol {
    private let apiClient: APIClientProtocol
    private let logger: any AppLoggerProtocol
    
    init(apiClient: APIClientProtocol, logger: any AppLoggerProtocol = AppLogger.shared) {
        self.apiClient = apiClient
        self.logger = logger
    }
    
    func getContactStatus() async throws -> APIResponse {
        let endpoint = StatusEndpoints.getContactStatus
        return try await apiClient.request(endpoint: endpoint)
    }

    func onPostStatus(_ request: CreateStatusRequest) async throws -> APIResponse {
        let endpoint = StatusEndpoints.onPostStatus(request)
        // chat-core/stories POST returns the created story object directly — shape varies
        // (camelCase vs snake_case). Treat HTTP 2xx as success; don't fail the local
        // sync badge just because the body couldn't map to StatusItemDTO.
        let _: JSONValue = try await apiClient.request(endpoint: endpoint)
        return .success(message: "Story created")
    }

    func deleteStatus(_ request: DeleteStatusRequest) async throws -> APIResponse {
        let endpoint = StatusEndpoints.deleteStatus(request)
        // chat-core/stories DELETE returns { statusCode, message, data } — not FeatureChat's `status` envelope.
        let response: StatusAPIResponseDTO<EmptyDTO> = try await apiClient.request(endpoint: endpoint)
        let code = response.statusCode ?? 0
        guard (200...299).contains(code) else {
            return APIResponse(
                status: code == 0 ? 500 : code,
                message: response.message ?? "Story delete failed"
            )
        }
        return .success(message: response.message ?? "Story deleted")
    }
    
    func syncStories(since: Date?, limit: Int) async throws -> StoriesSyncResponseDTO {
        let endpoint = StatusEndpoints.syncStories(since: since, limit: limit)
        return try await apiClient.request(endpoint: endpoint)
    }
}
