//
//  DynamicBillerUseCases.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//


public protocol GetBillerFormParamsUseCaseProtocol {
    func execute(billerFormId: String) async -> Result<DynamicBiller, AppError>
}

public protocol GetBillerCategoriesUseCaseProtocol {
    func execute() async -> Result<[BillerCategory], AppError>
}

/// Remplace les placeholders `fieldList_<fieldName>` puis appelle le backend (URL + méthode fournies par `fetchFieldForm`).
public protocol FetchBillerFieldFormUseCaseProtocol: Sendable {
    func execute(config: DynamicBillerFetchFieldForm, dataRequest: [String: String]) async -> Result<[String: String], AppError>
}

//MARK: FACTORY

public struct DynamicBillerUsecases: Sendable {

    public let getBillerFormParams: any GetBillerFormParamsUseCaseProtocol
    public let getBillerCategories: any GetBillerCategoriesUseCaseProtocol
    public let fetchFieldForm: any FetchBillerFieldFormUseCaseProtocol

    public init(
        getBillerFormParams: any GetBillerFormParamsUseCaseProtocol,
        getBillerCategories: any GetBillerCategoriesUseCaseProtocol,
        fetchFieldForm: any FetchBillerFieldFormUseCaseProtocol
    ) {
        self.getBillerFormParams = getBillerFormParams
        self.getBillerCategories = getBillerCategories
        self.fetchFieldForm = fetchFieldForm
    }
   
}
