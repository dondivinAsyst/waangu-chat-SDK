//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.

import Foundation
import WaanguCoreKit
import WaanguNetworkKit


public class LocationRepository: LocationRepositoryProtocol {

    
    private let dataSource: LocationDatasourceProtocol
    private let apiErrorMapper: ErrorMapperProtocol
    
    
     public init(
        dataSource: LocationDatasourceProtocol,
        apiErrorMapper: ErrorMapperProtocol
    ) {
        self.dataSource = dataSource
        self.apiErrorMapper = apiErrorMapper
    }
    
    public func findLocation(request: FindLocation) async -> Result<LocationResponseData, AppError> {
        do {
            let dto = LocationMappers.map(entity: request)
            
            let response = try await dataSource.findLocation(dto: dto)

            guard response.err == BusinessStatusCode.success.rawValue else {
                return .failure(.unknown(response.message))
            }

            guard let mapped = LocationMappers.map(responseDTO: response) else {
                return .failure(.unknown("No location found"))
            }
            return .success(mapped)

        } catch let apiError as APIError {
            return .failure(apiErrorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

}
