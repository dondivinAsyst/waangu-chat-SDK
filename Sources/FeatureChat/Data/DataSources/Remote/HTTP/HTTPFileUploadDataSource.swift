import Foundation
import WaanguCoreKit

protocol HTTPFileUploadDataSourceProtocol {
    func getPresignedURL(_ request: PresignedURLRequest) async throws -> PresignedURLResponse
    func completeUploadFile(_ request: CompleteFileUploadRequest) async throws -> CompleteUploadResponse
}

class HTTPFileUploadDataSource: HTTPFileUploadDataSourceProtocol {
    private let apiClient: APIClientProtocol
    private let logger: any AppLoggerProtocol
    
    init(apiClient: APIClientProtocol, logger: any AppLoggerProtocol = AppLogger.shared) {
        self.apiClient = apiClient
        self.logger = logger
    }
    
    func getPresignedURL(_ request: PresignedURLRequest) async throws -> PresignedURLResponse {
     
        let endpoint = FileUploadEndpoints.getPresignedURL(request)
        let res: PresignedURLResponse = try await apiClient.request(endpoint: endpoint)
//        let res: PresignedURLResponse = try await apiClient.uploadRequest(endpoint)
        debugLog("🔥 herrrrrr  \(res)")
        return res
    }
    func completeUploadFile(_ request: CompleteFileUploadRequest) async throws -> CompleteUploadResponse {
    
        let endpoint = FileUploadEndpoints.completeUpload(request)
        let res: CompleteUploadResponse = try await apiClient.request(endpoint: endpoint)
//        let res: CompleteUploadResponse = try await apiClient.uploadRequest(endpoint)
        debugLog("🔥 complete upload  \(res)")
        return res
    }
}
