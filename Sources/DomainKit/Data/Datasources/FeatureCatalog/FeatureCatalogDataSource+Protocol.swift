//
//  FeatureCatalogDataSource.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//
import Foundation
import WaanguNetworkKit
import WaanguCoreKit


protocol FeatureCatalogDataSourceProtocol {
    func getFeatureCatalog(forceRefresh:Bool) async throws -> FeatureCatalogResponseDTO
    func getFeatureCatalogVersion(request:FeatureCatalogVersionRequestDTO) async throws -> FeatureCatalogVersionResponseDTO
}


//MARK: IMPLEMENTATION DATASOURCE

class FeatureCatalogDataSource: FeatureCatalogDataSourceProtocol {

    private let apiClient: APIClientProtocol
    
    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    func getFeatureCatalogVersion(request: FeatureCatalogVersionRequestDTO) async throws -> FeatureCatalogVersionResponseDTO {
        let endpoint = FeatureCatalogEndpoints.getFeatureCatalogVersion(request)
        return try await apiClient.request(endpoint: endpoint)
    }
    
    func getFeatureCatalog(forceRefresh:Bool) async throws -> FeatureCatalogResponseDTO {
        let endpoint = FeatureCatalogEndpoints.getFeatureCatalog(forceRefresh: forceRefresh)
        return try await apiClient.request(endpoint: endpoint)
    }
}


