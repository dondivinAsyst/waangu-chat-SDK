//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguCoreKit


public protocol SharedFeatureRepositoryProtocol {
    func getBalance(forceRefresh:Bool) async -> Result<GetBalance, AppError>
    func checkRecipientPhone(phone: String) async -> Result<UserProfile, AppError>
    func getUserInfos() async -> Result<UserInfos, AppError>
    func countNewNotifications() async -> Result<CountNewNotification, AppError>
}
