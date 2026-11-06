//
//  WalletServicesUsecases.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//
import WaanguCoreKit


// MARK: - Use case implementations (internes à DomainKit)

struct GetAppUserServicesUsecases: GetAppUserServicesUsecasesProtocol {

    private let repository: AppUserServiceRepositoryProtocol

    init(repository: AppUserServiceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        type: TypeService,
        forcedRefresh: Bool = false
    ) async -> Result<[AppUserService], AppError> {
        await repository.getServices(request: type, forcedRefresh: forcedRefresh)
    }
}

struct GetAppUserServicesByCodeUsecase: GetAppUserServicesByCodeUsecaseProtocol {

    private let repository: AppUserServiceRepositoryProtocol

    init(repository: AppUserServiceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        serviceCode: ServiceCode,
        type: TypeService,
        forcedRefresh: Bool = false
    ) async -> Result<String, AppError> {
        let result = await repository.getServices(request: type, forcedRefresh: forcedRefresh)

        switch result {
        case .success(let services):
            if let service = services.first(where: { $0.code == serviceCode.rawValue }) {
                return .success(service.id)
            } else {
                return .failure(.unknown("Service with code \(serviceCode.rawValue) not found"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}

// MARK: - Factory (seul symbole public du fichier)

public enum AppUserServicesUsecasesFactory {

    public static func make(
        apiClient: any APIClientProtocol,
        errorMapper: any ErrorMapperProtocol,
    ) -> AppUserServicesUsecases {

        let api: AppUserServiceDatasourceProtocol = AppUserServiceDatasource(
            apiClient: apiClient
        )

        let repository = AppUserServiceRepository(
            api: api,
            errorMapper: errorMapper
        )

        return AppUserServicesUsecases(
            getAppUserServices: GetAppUserServicesUsecases(repository: repository),
            getAppUserServicesByCode: GetAppUserServicesByCodeUsecase(repository: repository)
        )
    }
}
