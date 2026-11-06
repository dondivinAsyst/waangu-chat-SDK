//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguCoreKit

struct GetBalanceUsecase : GetBalanceUseCaseProtocol {

    private let repository: any SharedFeatureRepositoryProtocol

    init(repository: SharedFeatureRepositoryProtocol) {
        self.repository = repository
    }

    func execute(forceRefresh:Bool) async -> Result<GetBalance, AppError> {
        await repository.getBalance(forceRefresh: forceRefresh)
    }
}

public struct CheckRecipientPhoneUseCase : CheckRecipientPhoneUseCaseProtocol{
    let repository: any SharedFeatureRepositoryProtocol

    public init(repository: SharedFeatureRepositoryProtocol) {
        self.repository = repository
    }

    public func execute(phone: String) async -> Result<UserProfile, AppError> {
        await repository.checkRecipientPhone(phone: phone)
    }
}

struct UserInfoUseCase: UserInfoUseCaseProtocol {
    private let repository: any SharedFeatureRepositoryProtocol

    init(repository: SharedFeatureRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async -> Result<UserInfos, AppError> {
        await repository.getUserInfos()
    }
}

struct CountNewNotificationsUseCase: CountNewNotificationUseCaseProtocol {

    private let repository: SharedFeatureRepositoryProtocol

    init(repository: SharedFeatureRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async -> Result<CountNewNotification, AppError> {
        await repository.countNewNotifications()
    }
}
//MARK: FACTORY

public enum SharedFeatureUseCaseFactory {

    public static func make(
        apiClient: any APIClientProtocol,
        errorMapper: any ErrorMapperProtocol
    ) -> SharedFeatureUsecases {

        let dataSource = SharedFeatureDatasource(apiClient: apiClient)

        let repository = SharedFeatureRepository(
            dataSource: dataSource,
            apiErrorMapper: errorMapper
        )

        return SharedFeatureUsecases(
            getBalance: GetBalanceUsecase(repository: repository),
            checkRecipientPhone: CheckRecipientPhoneUseCase(repository: repository),
            userInfo: UserInfoUseCase(repository: repository),
            countNewNotification: CountNewNotificationsUseCase(repository: repository)
        )
    }
}
