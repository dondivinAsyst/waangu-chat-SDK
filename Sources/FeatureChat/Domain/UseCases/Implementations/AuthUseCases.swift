//
//  AuthUseCases.swift
//  AppModules
//
//  Created by Don divin on 5/20/26.
//  Updated by Consolidation on 6/16/26 - Enhanced AppSettings integration
//

import Foundation
import WaanguCoreKit

class AuthenticateUseCase: AuthenticateUseCaseProtocol {
    private let repository: AuthRepositoryProtocol
    private var appSettings: any AppSettingsProtocol
    
    init(repository: AuthRepositoryProtocol, appSettings: any AppSettingsProtocol) {
        self.repository = repository
        self.appSettings = appSettings
    }
    
    func execute() async -> AuthSessionInfo? {
        let session = await repository.authenticate()
        
        // Update AppSettings with session data
        if let session = session {
            appSettings.chatSessionID = session.sessionId
            appSettings.chatSessionExpireDate = session.expiresAt
            appSettings.currentUserId = session.userId
            appSettings.currentUserPhone = session.phone
            appSettings.currentUserName = session.name
            appSettings.currentUserFullName = session.name
            appSettings.currentUserTenantId = session.tenantId
            appSettings.currentUserOrganisationId = session.organisationId
            appSettings.lastLoginDate = Date()
            appSettings.isAuthenticated = true
            
        } else {
            appSettings.isAuthenticated = false
        }
        
        return session
    }
}

class AuthUseCases: AuthUseCasesProtocol {
    let authenticate: AuthenticateUseCaseProtocol
    
    init(repository: AuthRepositoryProtocol, appSettings: any AppSettingsProtocol) {
        self.authenticate = AuthenticateUseCase(repository: repository, appSettings: appSettings)
    }
}

