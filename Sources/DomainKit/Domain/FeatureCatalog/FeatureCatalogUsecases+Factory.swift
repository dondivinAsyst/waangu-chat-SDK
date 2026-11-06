//
//  usecases.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import Foundation
import WaanguCoreKit

struct GetFeatureCatalogUseCase : GetFeatureCatalogUseCaseProtocol {

    private let repository: any FeatureCatalogRepositoryProtocol

    init(repository: FeatureCatalogRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async -> Result<[FeatureCatalog], AppError> {
        await repository.getFeatureCatalog(forceRefresh: false)
    }
}

struct GetFeatureCatalogVersionUseCase : GetFeatureCatalogVersionUseCaseProtocol {

    private let repository: any FeatureCatalogRepositoryProtocol

    init(repository: FeatureCatalogRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async -> Result<FeatureCatalogVersionResult, AppError> {
        let req = FeatureCatalogVersionRequestDTO(version: "String", country: "String")
        return await repository.getFeatureCatalogVersion(request: req )
       
    }
}


struct RefreshFeatureCatalogUseCase : RefreshFeatureCatalogUseCaseProtocol {

    private let repository: any FeatureCatalogRepositoryProtocol
    private let appSettings: any AppSettingsProtocol

    init(repository: FeatureCatalogRepositoryProtocol, appSettings: any AppSettingsProtocol) {
        self.repository = repository
        self.appSettings = appSettings
    }

    func execute() async -> Result<[FeatureCatalog], AppError> {
        let req = FeatureCatalogVersionRequestDTO(version: "String", country: "String")
        return await repository.getFeatureCatalog(forceRefresh: true)
       
    }
}

struct GetFeatureCatalogByTypeUseCase : GetFeatureCatalogByTypeUseCaseProtocol {

    private let repository: any FeatureCatalogRepositoryProtocol

    init(repository: FeatureCatalogRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(type: FeatureType) async -> Result<[FeatureCatalog], AppError> {
        
        let result = await repository.getFeatureCatalog(forceRefresh: false)
        
        switch result {
            
        case .success(let icons):
            
         switch type {
                
            case .transfer:
                return .success(icons.filter { $0.form == type.rawValue })
            case .quickAction:
                return .success(icons.filter { $0.form == type.rawValue })
            case .cashOutService:
                return .success(icons.filter { $0.form == type.rawValue })
            case .cashInService:
                return .success(icons.filter { $0.form == type.rawValue})
            case .requestTransfer:
               return .success(icons.filter({ $0.form == type.rawValue}))
            case .water:
              return .success(icons.filter({ $0.form == type.rawValue}))
            case .ewa:
                return .success(icons.filter({ $0.form == type.rawValue}))
             }
         case .failure(let error):
            return .failure(error )
        }

    }

}

//MARK: FACTORY

public enum FeatureCatalogUseCaseFactory {

    public static func make(
        apiClient: any APIClientProtocol,
        errorMapper: any ErrorMapperProtocol,
        appSettings: any AppSettingsProtocol
    ) -> FeatureCatalogUsecases {

        let dataSource = FeatureCatalogDataSource(apiClient: apiClient)

        let repository = FeatureCatalogRepository(
            dataSource: dataSource,
            apiErrorMapper: errorMapper
        )

        return FeatureCatalogUsecases(
            getFeatureCatalog: GetFeatureCatalogUseCase(repository: repository),
            getFeatureCatalogVersion: GetFeatureCatalogVersionUseCase(repository: repository),
            refreshFeatureCatalog: RefreshFeatureCatalogUseCase(repository: repository, appSettings: appSettings),
            getFeatureCatalogByType: GetFeatureCatalogByTypeUseCase(repository: repository)
        )
    }
}


