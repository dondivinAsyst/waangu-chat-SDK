//
//  FeatureCatalogRepository.swift.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit


class FeatureCatalogRepository: FeatureCatalogRepositoryProtocol {

    
    private let dataSource: FeatureCatalogDataSourceProtocol
    private let apiErrorMapper: ErrorMapperProtocol
    
    
    init(
        dataSource: FeatureCatalogDataSourceProtocol,
        apiErrorMapper: ErrorMapperProtocol
    ) {
        self.dataSource = dataSource
        self.apiErrorMapper = apiErrorMapper
    }
    
    func getFeatureCatalogVersion(request: FeatureCatalogVersionRequestDTO) async -> Result<FeatureCatalogVersionResult, AppError> {
        do {
            let response = try await dataSource.getFeatureCatalogVersion(request:request)
            
            if response.err == BusinessStatusCode.success.rawValue {
                if response.refresh {
                    return .success(.forceRefreshIcon)
                }else{
                    return .success(.noNeedToRefreshIcon)
                }
            }else{
                return .failure(.unknown(response.message))
            }

        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
    
    func getFeatureCatalog(forceRefresh:Bool) async -> Result<[FeatureCatalog], AppError> {
        do {
            let response = try await dataSource.getFeatureCatalog(forceRefresh: forceRefresh)
            
            guard let featureCatalog = response.data else {
                return .failure(.unknown("No home icons data returned"))
            }
            
            let data = featureCatalog.map { FeatureCatalogMappers.toDomain($0) }
            return .success(data)
        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
