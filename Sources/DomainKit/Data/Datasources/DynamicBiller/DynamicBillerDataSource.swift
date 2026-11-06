//
//  DynamicBillerDataSource.swift
//  DomainKit — appels `apiClient.request(endpoint:)` comme HTTPAuthDataSource (FeatureAuth).
//

import WaanguCoreKit
import Foundation

final class DynamicBillerDataSource: DynamicBillerDataSourceProtocol, @unchecked Sendable {

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func getBillerFormParams(_ request: BillerFormRequestDTO) async throws -> DynamicBillerResponseDTO {
        try await apiClient.request(endpoint: DynamicBillerEndpoints.getBillerFormParams(request))
    }

    func getBillerCategories() async throws -> BillerCategoriesResponseDTO {
        try await apiClient.request(endpoint: DynamicBillerEndpoints.getBillerCategories)
    }

    func fetchFieldForm(_ request: FetchFieldFormRequestDTO) async throws -> FetchFieldFormResponseDTO {
        try await apiClient.request(
            endpoint: DynamicBillerEndpoints.fetchFieldForm(
                url: request.url,
                httpMethod: request.httpMethod,
                body: request.body
            )
        )
    }
}
