//
//  DataSource.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//
import Foundation
import WaanguNetworkKit
import WaanguCoreKit

public protocol SharedFeatureDatasourceProtocol {
    func getBalance(forceRefresh:Bool) async throws -> GetBalanceResponseDTO
    func checkRecipientPhone(dto: CheckCustomerPhoneRequestDTO) async throws -> UserProfileResponseDTO
    func getUserInfos() async throws -> UserInfosResponseDTO
    func countNewNotifications() async throws -> CountNewNotificationResponseDTO
}


//MARK: IMPLEMENTATION DATASOURCE

public class SharedFeatureDatasource: SharedFeatureDatasourceProtocol {
  
    private let apiClient: APIClientProtocol
    
    public init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }
    
    public func getBalance(forceRefresh:Bool) async throws -> GetBalanceResponseDTO {
        let endpoint = SharedFeatureEndpoints.getBalance(forceRefresh: false)
        return try await apiClient.request(endpoint: endpoint)
    }
    
    public func checkRecipientPhone(dto: CheckCustomerPhoneRequestDTO) async throws -> UserProfileResponseDTO {
        let endpoint = SharedFeatureEndpoints.checkRecipientPhone(dto)
        return try await apiClient.request(endpoint: endpoint)
    }

    public func getUserInfos() async throws -> UserInfosResponseDTO {
        let endpoint = SharedFeatureEndpoints.getUserInfos
        return try await apiClient.request(endpoint: endpoint)
    }
    
    public func countNewNotifications() async throws -> CountNewNotificationResponseDTO {
        let endpoint = SharedFeatureEndpoints.countNewNotifications
        return try await apiClient.request(endpoint: endpoint)
    }
}

