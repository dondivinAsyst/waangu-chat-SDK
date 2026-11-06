//
//  DataSource.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//
import Foundation
import WaanguNetworkKit
import WaanguCoreKit

public protocol LocationDatasourceProtocol {
    func findLocation(dto: FindLocationRequestDTO) async throws -> FindLocationResponseDTO
}


//MARK: IMPLEMENTATION DATASOURCE

public class LocationDatasource: LocationDatasourceProtocol {
  
    private let apiClient: APIClientProtocol
    
    public init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    public func findLocation(dto: FindLocationRequestDTO) async throws -> FindLocationResponseDTO {
        let endpoint = LocationEndpoints.findLocation(dto)
        return try await apiClient.request(endpoint: endpoint)
    }
}

