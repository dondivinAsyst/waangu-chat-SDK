//
//  DynamicBillerDataSourceProtocol.swift
//  DomainKit — même esprit que HTTPAuthDataSourceProtocol (FeatureAuth).
//

import Foundation

protocol DynamicBillerDataSourceProtocol: Sendable {
    func getBillerFormParams(_ request: BillerFormRequestDTO) async throws -> DynamicBillerResponseDTO
    func getBillerCategories() async throws -> BillerCategoriesResponseDTO
    func fetchFieldForm(_ request: FetchFieldFormRequestDTO) async throws -> FetchFieldFormResponseDTO
}
