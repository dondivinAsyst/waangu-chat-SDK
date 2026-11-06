//
//  UserServices.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//
import Foundation



public protocol GetAppUserServicesUsecasesProtocol: Sendable {
    func execute(
        type: TypeService,
        forcedRefresh: Bool
    ) async -> Result<[AppUserService], AppError>
}

public protocol GetAppUserServicesByCodeUsecaseProtocol: Sendable {
    func execute(
        serviceCode: ServiceCode,
        type: TypeService,
        forcedRefresh: Bool
    ) async -> Result<String, AppError>
}


public struct AppUserServicesUsecases: Sendable {
    public let getAppUserServices: any GetAppUserServicesUsecasesProtocol
    public let getAppUserServicesByCode: any GetAppUserServicesByCodeUsecaseProtocol

    public init(
        getAppUserServices: any GetAppUserServicesUsecasesProtocol,
        getAppUserServicesByCode: any GetAppUserServicesByCodeUsecaseProtocol
    ) {
        self.getAppUserServices = getAppUserServices
        self.getAppUserServicesByCode = getAppUserServicesByCode
    }
}
