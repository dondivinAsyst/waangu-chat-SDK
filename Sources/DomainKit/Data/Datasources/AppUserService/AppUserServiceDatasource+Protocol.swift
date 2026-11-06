//
//  DataSource.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//
import Foundation
import WaanguNetworkKit
import WaanguCoreKit

protocol AppUserServiceDatasourceProtocol {
    func getAppUserServices(
        request: AppUserServiceRequestDTO, forcedRefresh: Bool
    ) async throws -> AppUserServiceResponseDTO
}


//MARK: IMPLEMENTATION DATASOURCE

class AppUserServiceDatasource: AppUserServiceDatasourceProtocol {
  
    private let apiClient: APIClientProtocol
    
    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    func getAppUserServices(
        request: AppUserServiceRequestDTO, forcedRefresh: Bool
    ) async throws -> AppUserServiceResponseDTO {
        let endpoint = AppUserServiceEndpoints.getServiceList(request: request, forcedRefresh: forcedRefresh)
        return try await apiClient.request(endpoint: endpoint)
    }
}

