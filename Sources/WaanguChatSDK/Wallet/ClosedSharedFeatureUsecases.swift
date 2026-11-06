//
//  ClosedSharedFeatureUsecases.swift
//  WaanguChatSDK
//
//  Stand-ins for a host without a wallet (SDK plan, step 1.9).
//

import Foundation
import WaanguCoreKit

/// `ChatDependencies.sharedFeatureUsecases` is required, but chat only reads it as the finance
/// balance when no balance override is given. A host without a wallet has nothing to answer
/// with, so every use case reports the service as unavailable, never an invented value.
struct ClosedSharedFeatureUsecases: SharedFeatureUsecasesProtocol {
    var getBalance: any GetBalanceUseCaseProtocol { Unavailable() }
    var checkRecipientPhone: any CheckRecipientPhoneUseCaseProtocol { Unavailable() }
    var userInfo: any UserInfoUseCaseProtocol { Unavailable() }
    var countNewNotification: any CountNewNotificationUseCaseProtocol { Unavailable() }

    private struct Unavailable:
        GetBalanceUseCaseProtocol,
        CheckRecipientPhoneUseCaseProtocol,
        UserInfoUseCaseProtocol,
        CountNewNotificationUseCaseProtocol
    {
        func execute(forceRefresh: Bool) async -> Result<GetBalance, AppError> { .failure(.serviceUnavailable) }
        func execute(phone: String) async -> Result<UserProfile, AppError> { .failure(.serviceUnavailable) }
        func execute() async -> Result<UserInfos, AppError> { .failure(.serviceUnavailable) }
        func execute() async -> Result<CountNewNotification, AppError> { .failure(.serviceUnavailable) }
    }
}
