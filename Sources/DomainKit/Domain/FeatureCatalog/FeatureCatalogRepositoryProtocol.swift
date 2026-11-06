//
//  FeatureCatalogRepositoryProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//


import Foundation
import WaanguCoreKit


protocol FeatureCatalogRepositoryProtocol {
    func getFeatureCatalog(forceRefresh:Bool) async -> Result<[FeatureCatalog], AppError>
    func getFeatureCatalogVersion(request: FeatureCatalogVersionRequestDTO) async -> Result<FeatureCatalogVersionResult, AppError>
}
