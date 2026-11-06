//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguCoreKit

struct FindLocationUsecase : FindLocationUseCaseProtocol {

    private let repository: any LocationRepositoryProtocol

    init(repository: LocationRepositoryProtocol) {
        self.repository = repository
    }

    func execute(request: FindLocation) async -> Result<LocationResponseData, AppError> {
        await repository.findLocation(request: request)
    }
}

//MARK: FACTORY

public enum LocationUseCaseFactory {

    public static func make(
        apiClient: any APIClientProtocol,
        errorMapper: any ErrorMapperProtocol
    ) -> LocationUsecases {
        
        let dataSource = LocationDatasource(apiClient: apiClient)
        
        let repository = LocationRepository(
            dataSource: dataSource,
            apiErrorMapper: errorMapper
        )
        
        let findLocationUseCase = FindLocationUsecase(repository: repository)
        
        return LocationUsecases(
            findLocation: findLocationUseCase
        )
    }
}
