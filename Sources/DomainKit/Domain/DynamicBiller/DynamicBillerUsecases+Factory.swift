//
//  DynamicBillerUsecases+Factory.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import Foundation
import WaanguCoreKit

struct GetBillerFormParamsUseCase: GetBillerFormParamsUseCaseProtocol {
    private let repository: any DynamicBillerRepositoryProtocol
    
    init(repository: DynamicBillerRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(billerFormId: String) async -> Result<DynamicBiller, AppError> {
        await repository.getBillerFormParams(billerFormId: billerFormId)
    }
}

struct GetBillerCategoriesUseCase: GetBillerCategoriesUseCaseProtocol {
    private let repository: any DynamicBillerRepositoryProtocol
    
    init(repository: DynamicBillerRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async -> Result<[BillerCategory], AppError> {
        await repository.getBillerCategories()
    }
}

struct FetchBillerFieldFormUseCase: FetchBillerFieldFormUseCaseProtocol {
    private let repository: any DynamicBillerRepositoryProtocol

    init(repository: DynamicBillerRepositoryProtocol) {
        self.repository = repository
    }

    func execute(config: DynamicBillerFetchFieldForm, dataRequest: [String: String]) async -> Result<[String: String], AppError> {
        var body = config.data
        for (key, value) in body where value.contains("fieldList") {
            let parts = value.split(separator: "_", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let fieldName = String(parts[1])
            body[key] = dataRequest[fieldName]
        }
        return await repository.fetchFieldForm(url: config.url, method: config.method, body: body)
    }
}

public enum DynamicBillerUseCaseFactory {
    public static func make(
        apiClient: any APIClientProtocol,
        errorMapper: any ErrorMapperProtocol
    ) -> DynamicBillerUsecases {
        let dataSource = DynamicBillerDataSource(apiClient: apiClient)
        
        let repository = DynamicBillerRepository(
            dataSource: dataSource,
            apiErrorMapper: errorMapper
        )
        
        return DynamicBillerUsecases(
            getBillerFormParams: GetBillerFormParamsUseCase(repository: repository),
            getBillerCategories: GetBillerCategoriesUseCase(repository: repository),
            fetchFieldForm: FetchBillerFieldFormUseCase(repository: repository)
        )
    }
}
