//
//  HTTPAuthDatasource.swift
//  AppModules
//
//  Created by Don divin on 5/20/26.
//

import Foundation
import WaanguCoreKit

protocol HTTPAuthDataSourceProtocol {
    func authenticate(_ request: AuthRequest) async throws -> APIAuthResponse
}

class HTTPAuthDataSource: HTTPAuthDataSourceProtocol {
  
    private let apiClient: APIClientProtocol
    private let appId: String
    private let logger: any AppLoggerProtocol
    
    init(apiClient: APIClientProtocol, appId: String, logger: any AppLoggerProtocol = AppLogger.shared) {
        self.apiClient = apiClient
        self.appId = appId
        self.logger = logger
    }
    
    func authenticate(_ request: AuthRequest) async throws -> APIAuthResponse {
    
        let req = AuthChatEndpoint.authenticate(request: request, appId: appId)
        let res: APIAuthResponse = try await apiClient.request(endpoint:req)

        return res
    }
}
