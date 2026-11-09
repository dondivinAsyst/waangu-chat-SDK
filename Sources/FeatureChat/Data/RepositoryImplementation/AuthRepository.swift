//
//  AuthRepository.swift
//  AppModules
//
//  Created by Don divin on 5/20/26.
//

import Foundation
import WaanguCoreKit

public class AuthRepository: AuthRepositoryProtocol {
    let httpDatasource: HTTPAuthDataSourceProtocol
    private let deviceInfoProvider: DeviceInfoProvidingProtocol
    private let logger: any AppLoggerProtocol = AppLogger.shared
    private let chatTokenManager: any ChatTokenManagerProtocol
    private let userIdentifier: String?
    
    init(
        deviceInfoProvider: DeviceInfoProvidingProtocol,
        httpDataSource: HTTPAuthDataSourceProtocol,
        chatTokenManager: any ChatTokenManagerProtocol,
        userIdentifier: String? = nil
    ) {
        self.httpDatasource = httpDataSource
        self.deviceInfoProvider = deviceInfoProvider
        self.chatTokenManager = chatTokenManager
        self.userIdentifier = userIdentifier
    }
   public func authenticate() async -> AuthSessionInfo? {
       // Plan SDK, step 1.3. Who the user is: the `appUserId` that the app's `verify-user`
       // webhook returns for the Bearer token (Identity, answer of 2026-11-05). For the time being
       // the host can also pass a `userIdentifier` (AppConfiguration.chatUserId), sent as
       // `user_identifier`; with none, nothing is sent and this does not depend on the wallet.
       let req = AuthRequest.mapper(deviceInfo: deviceInfoProvider.captureDeviceContext(), userIdentifier: userIdentifier)
//       let req = AuthRequest.fakeUser
       
       do {
           let res = await try httpDatasource.authenticate(req)
           guard (200...299).contains(res.status) else {
               await logger.log("👀Authentication Failed \(res.message)", level: .info)
               return nil
           }
           let auth = res.data.toAuthInfo()
//           let auth = AuthSessionData.toFakeAuthInfo()
           
          try await chatTokenManager.saveTokens(
            accessToken: auth.sessionId,
            accessTokenExpiration: auth.expiresAt,
            refreshToken: auth.sessionId,
            refreshTokenExpiration: auth.expiresAt
           )
           
           return auth
       } catch {
           await logger.log("👀error occur while authenticate \(error.localizedDescription)", level: .error)
           return nil
       }
       
       return nil
    }
}
