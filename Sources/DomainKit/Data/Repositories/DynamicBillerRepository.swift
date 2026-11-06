//
//  DynamicBillerRepository.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

class DynamicBillerRepository: DynamicBillerRepositoryProtocol {
    private let dataSource: DynamicBillerDataSourceProtocol
    private let apiErrorMapper: ErrorMapperProtocol
    
    init(
        dataSource: DynamicBillerDataSourceProtocol,
        apiErrorMapper: ErrorMapperProtocol
    ) {
        self.dataSource = dataSource
        self.apiErrorMapper = apiErrorMapper
    }
    
    func getBillerFormParams(billerFormId: String) async -> Result<DynamicBiller, AppError> {
        do {
            let request = BillerFormRequestDTO(billerFormId: billerFormId)
            let response = try await dataSource.getBillerFormParams(request)
            
            guard response.err == BusinessStatusCode.success.rawValue else {
                return .failure(.unknown(response.message))
            }
            
            return .success(DynamicBillerMappers.toDomain(response.data))
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
    
    func getBillerCategories() async -> Result<[BillerCategory], AppError> {
        do {
            let response = try await dataSource.getBillerCategories()
            
            guard response.err == BusinessStatusCode.success.rawValue else {
                return .failure(.unknown(response.message))
            }
            
            return .success(response.data.map { DynamicBillerMappers.toDomain($0) })
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

    func fetchFieldForm(url: String, method: String, body: [String: String]) async -> Result<[String: String], AppError> {
        do {
            let request = FetchFieldFormRequestDTO(url: url, method: method, body: body)
            let response = try await dataSource.fetchFieldForm(request)
            guard response.err == BusinessStatusCode.success.rawValue else {
                return .failure(.unknown(response.message))
            }
            return .success(response.data)
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
