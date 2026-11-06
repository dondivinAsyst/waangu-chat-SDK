//
//  CurrentSessionUseCase.swift
//  FeatureChat
//
//  Created by Architecture Team on 6/4/26.
//  Updated by Consolidation on 6/16/26 - Converted to use AppSettings directly
//

import Foundation
import WaanguCoreKit

/// Session use case that now delegates to AppSettings
/// DEPRECATED: Use AppSettings directly for new code
public final class CurrentSessionUseCase: CurrentSessionUseCaseProtocol {
    private var appSettings: any AppSettingsProtocol

    public init(appSettings: any AppSettingsProtocol) {
        self.appSettings = appSettings
    }

    public func saveAuthenticatedSession(_ authInfo: AuthSessionInfo) async throws -> CurrentSession {
        // Update AppSettings directly (this is now the source of truth)
        appSettings.currentUserId = authInfo.userId
        appSettings.currentUserPhone = authInfo.phone
        appSettings.currentUserName = authInfo.name
        appSettings.currentUserFullName = authInfo.name
        appSettings.currentUserTenantId = authInfo.tenantId
        appSettings.currentUserOrganisationId = authInfo.organisationId
        appSettings.chatSessionID = authInfo.sessionId
        appSettings.chatSessionExpireDate = authInfo.expiresAt
        appSettings.lastLoginDate = Date()
        appSettings.isAuthenticated = true

        // Update CurrentSessionInfo.shared for backward compatibility
        CurrentSessionInfo.shared.update(from: authInfo)

        // Return legacy CurrentSession model for compatibility
        return CurrentSession(
            redirectUrl: authInfo.redirectUrl,
            sessionId: authInfo.sessionId,
            appId: authInfo.appId,
            userId: authInfo.userId,
            email: authInfo.email,
            name: authInfo.name,
            tenantId: authInfo.tenantId,
            organisationId: authInfo.organisationId,
            country: authInfo.country,
            phone: authInfo.phone,
            expiresAt: authInfo.expiresAt,
            lastAuthenticatedAt: Date()
        )
    }

    public func loadCurrentSession() async throws -> CurrentSession? {
        // Check AppSettings for session data
        guard appSettings.isAuthenticated,
              let userId = appSettings.currentUserId,
              !userId.isEmpty,
              !appSettings.chatSessionID.isEmpty else {
            debugLog("No valid session found in AppSettings (session empty: \(appSettings.chatSessionID.isEmpty))")
            return nil
        }

        // Build CurrentSession from AppSettings data
        let session = CurrentSession(
            redirectUrl: "",  // Not persisted in AppSettings
            sessionId: appSettings.chatSessionID,
            appId: "",       // Not persisted in AppSettings
            userId: userId,
            email: "",       // Not persisted in AppSettings
            name: appSettings.currentUserFullName ?? appSettings.currentUserName ?? "",
            tenantId: appSettings.currentUserTenantId ?? "",
            organisationId: appSettings.currentUserOrganisationId ?? "",
            country: "",     // Not persisted in AppSettings
            phone: appSettings.currentUserPhone ?? "",
            expiresAt: appSettings.chatSessionExpireDate,
            lastAuthenticatedAt: appSettings.lastLoginDate ?? Date()
        )
        
        // Update CurrentSessionInfo.shared for backward compatibility
        CurrentSessionInfo.shared.update(from: session)
        
        debugLog("Session loaded from AppSettings: \(session)")
        return session
    }

    public func clearSession() async throws {
        appSettings.clearSession()
        CurrentSessionInfo.shared.clear()
    }

    public func shouldReauthenticate() async throws -> Bool {
        // Check session expiration
        if let expiresAt = appSettings.chatSessionExpireDate {
            return Date() > expiresAt
        }
        
        // Check 24-hour re-authentication rule
        guard let lastAuth = appSettings.lastLoginDate else { return true }
        let hoursSinceAuth = Date().timeIntervalSince(lastAuth) / 3600
        return hoursSinceAuth >= 24
    }
}
