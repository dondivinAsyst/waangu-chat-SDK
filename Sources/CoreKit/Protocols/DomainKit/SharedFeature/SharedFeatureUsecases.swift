//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation

public protocol GetBalanceUseCaseProtocol {
    func execute(forceRefresh: Bool) async -> Result<GetBalance, AppError>
}
public protocol CheckRecipientPhoneUseCaseProtocol {
    func execute(phone: String) async -> Result<UserProfile, AppError>
}
public protocol UserInfoUseCaseProtocol {
    func execute() async -> Result<UserInfos, AppError>
}

public protocol CountNewNotificationUseCaseProtocol {
    func execute() async -> Result<CountNewNotification, AppError>
}
//MARK: FACTORY

public struct SharedFeatureUsecases: SharedFeatureUsecasesProtocol {
    public let getBalance: any GetBalanceUseCaseProtocol
    public let checkRecipientPhone: any CheckRecipientPhoneUseCaseProtocol
    public let userInfo: any UserInfoUseCaseProtocol
    public let countNewNotification: any CountNewNotificationUseCaseProtocol

    public init(
        getBalance: any GetBalanceUseCaseProtocol,
        checkRecipientPhone: any CheckRecipientPhoneUseCaseProtocol,
        userInfo: any UserInfoUseCaseProtocol,
        countNewNotification: any CountNewNotificationUseCaseProtocol
    ) {
        self.getBalance = getBalance
        self.checkRecipientPhone = checkRecipientPhone
        self.userInfo = userInfo
        self.countNewNotification = countNewNotification
    }
   
}
