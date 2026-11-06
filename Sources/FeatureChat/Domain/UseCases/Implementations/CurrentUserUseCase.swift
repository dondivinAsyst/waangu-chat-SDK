//
//  CurrentUserUseCase.swift
//  FeatureChat
//
//  Created by Architecture Team on 5/28/26.
//  Updated by Consolidation on 6/16/26 - Converted to use AppSettings directly
//

import Foundation
import WaanguCoreKit

/// Current user use case that now delegates to AppSettings
/// DEPRECATED: Use AppSettings directly for new code
public final class CurrentUserUseCase: CurrentUserUseCaseProtocol {
    
    private let appSettings: any AppSettingsProtocol
    
    public init(appSettings: any AppSettingsProtocol) {
        self.appSettings = appSettings
    }
    
    public func loadCurrentUser() async throws -> CurrentUser? {
        // Check if user is authenticated via AppSettings
        guard appSettings.isAuthenticated, 
              let userId = appSettings.currentUserId,
              !userId.isEmpty else {
            return nil
        }

        // CurrentUser.shared now delegates to AppSettings, so just return it
        // The singleton will automatically reflect AppSettings data
        return CurrentUser.shared
    }
    
    public func logout() async throws {
        // Clear session via AppSettings (this will automatically clear CurrentUser.shared)
        appSettings.clearSession()
        
        // Also explicitly clear CurrentUser.shared for safety
        CurrentUser.shared.clear()
    }
    
    public func shouldReauthenticate() async throws -> Bool {
        // Use AppSettings session expiration logic
        if appSettings.hasChatSessionExpired {
            return true
        }
        
        // Check 24-hour re-authentication rule
        guard let lastAuth = appSettings.lastLoginDate else { return true }
        let hoursSinceAuth = Date().timeIntervalSince(lastAuth) / 3600
        return hoursSinceAuth >= 24
    }
}
