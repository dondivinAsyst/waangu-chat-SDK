//
//  WalletServiceRepositoryProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import Foundation
import WaanguCoreKit

 public protocol AppUserServiceRepositoryProtocol: Sendable {
     func getServices(request: TypeService, forcedRefresh: Bool) async -> Result< [AppUserService] , AppError>
 
}
