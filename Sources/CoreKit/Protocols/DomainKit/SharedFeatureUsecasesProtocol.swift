//
//  SharedFeatureUsecasesProtocol.swift
//  CoreKit
//
//  Protocol abstraction for SharedFeatureUsecases

import Foundation

public protocol SharedFeatureUsecasesProtocol: Sendable {
    var getBalance: any GetBalanceUseCaseProtocol { get }
    var checkRecipientPhone: any CheckRecipientPhoneUseCaseProtocol { get }
    var userInfo: any UserInfoUseCaseProtocol { get }
    var countNewNotification: any CountNewNotificationUseCaseProtocol { get }
}