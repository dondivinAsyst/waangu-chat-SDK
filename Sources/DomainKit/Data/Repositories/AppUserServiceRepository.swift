//
//  WalletServiceRepository.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import Foundation
import WaanguCoreKit

final class AppUserServiceRepository: AppUserServiceRepositoryProtocol, @unchecked Sendable {

    private let api: AppUserServiceDatasourceProtocol
    private let errorMapper: ErrorMapperProtocol

    init(
        api: AppUserServiceDatasourceProtocol,
        errorMapper: ErrorMapperProtocol,
    ) {
        self.api = api
        self.errorMapper = errorMapper
    }

    func getServices(
        request: TypeService, forcedRefresh: Bool = false
    ) async -> Result< [AppUserService] , AppError> {
        
        let req = AppUserServicesMappers.map(from: request)
        
        do {
            let response = try await api.getAppUserServices(request: req, forcedRefresh: forcedRefresh)
            if response.err == BusinessStatusCode.success.rawValue {
                return .success(
                    AppUserServicesMappers.map(from: response)
                )
            }else{
                return .failure(.unknown(response.message))
            }
           
        } catch {
            return .failure(errorMapper.map(error))
        }
    }

}
