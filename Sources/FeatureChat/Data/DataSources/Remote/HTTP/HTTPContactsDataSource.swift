import Foundation
import WaanguCoreKit

protocol HTTPContactsDataSourceProtocol {
    func getContacts(_ request: ContactRequest) async throws -> APIContactResponse
    func blockOrUnblockContact(endpoint: ContactsEndpoints) async throws -> BlockContactResponse
}

class HTTPContactsDataSource: HTTPContactsDataSourceProtocol {
    private let apiClient: APIClientProtocol
    private let logger: any AppLoggerProtocol
    
    init(apiClient: APIClientProtocol, logger: any AppLoggerProtocol = AppLogger.shared) {
        self.apiClient = apiClient
        self.logger = logger
    }
    
    func getContacts(_ request: ContactRequest) async throws -> APIContactResponse {
        
        let req = ContactsEndpoints.getContacts(request)
        debugLog("🔥🔥🔥 getting contact request  \(req)")
        let res: APIContactResponse = try await apiClient.request(endpoint:req)
        debugLog("🔥🔥🔥 getting contact response  \(res)")
        return res
    }
    
    func blockOrUnblockContact(endpoint: ContactsEndpoints) async throws -> BlockContactResponse {
       
//        return BlockContactResponse(success: true, message: "this was blocked", contactId: "123456789", isBlocked: true)
        return try await apiClient.request(endpoint: endpoint)
    }
}
