//
//  FeatureCatalogUsecases.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

public protocol GetFeatureCatalogUseCaseProtocol {
    func execute() async -> Result<[FeatureCatalog], AppError>
}

public protocol GetFeatureCatalogVersionUseCaseProtocol {
    func execute() async -> Result<FeatureCatalogVersionResult, AppError>
}

public protocol RefreshFeatureCatalogUseCaseProtocol {
    func execute() async -> Result<[FeatureCatalog], AppError>
}

public enum FeatureType: String, CaseIterable {
    case transfer = "Transfer"
    case quickAction = "quickActions"
    case cashOutService = "Cashin"
    case cashInService = "Cashout"
    case requestTransfer = "RequestTransfer"
    case water = "Water"
    case ewa = "EWA"
    
    /// Mapping pour lookup rapide par string (ex: depuis `FeatureCatalog.form`)
    public static let mapByRawValue: [String: FeatureType] = {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0) })
    }()
}

public protocol GetFeatureCatalogByTypeUseCaseProtocol {
    func execute(type: FeatureType) async -> Result<[FeatureCatalog], AppError>
}



//MARK: FACTORY

public struct FeatureCatalogUsecases: Sendable {
    public let getFeatureCatalog : any GetFeatureCatalogUseCaseProtocol
    public let getFeatureCatalogVersion : any GetFeatureCatalogVersionUseCaseProtocol
    public let refreshFeatureCatalog : any RefreshFeatureCatalogUseCaseProtocol
    public let getFeatureCatalogByType : any GetFeatureCatalogByTypeUseCaseProtocol
   
    public init(
        getFeatureCatalog: any GetFeatureCatalogUseCaseProtocol,
        getFeatureCatalogVersion: any GetFeatureCatalogVersionUseCaseProtocol,
        refreshFeatureCatalog: any RefreshFeatureCatalogUseCaseProtocol,
        getFeatureCatalogByType : any GetFeatureCatalogByTypeUseCaseProtocol,
    ) {
        self.getFeatureCatalog = getFeatureCatalog
        self.getFeatureCatalogVersion = getFeatureCatalogVersion
        self.refreshFeatureCatalog = refreshFeatureCatalog
        self.getFeatureCatalogByType = getFeatureCatalogByType
    }
   
}
