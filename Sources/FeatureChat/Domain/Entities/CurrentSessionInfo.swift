//
//  CurrentSessionInfo.swift
//  FeatureChat
//
//  Created by Architecture Team on 6/5/26.
//  Updated by Consolidation on 6/16/26 - Converted to legacy compatibility adapter for AppSettings
//

import Foundation
import WaanguCoreKit

/// Runtime session singleton for FeatureChat - legacy compatibility adapter
/// Delegates to AppSettings for persistence while maintaining backward compatibility
/// DEPRECATED: Use AppSettings directly for new code
public final class CurrentSessionInfo {
    public static let shared = CurrentSessionInfo()

    private var appSettings: (any AppSettingsProtocol)?
    
    private init() {
        // No dependencies in init - will be injected later
    }
    
    // Injection method for AppSettings (called by ChatFeature during initialization)
    public func configure(appSettings: any AppSettingsProtocol) {
        self.appSettings = appSettings
    }

    // MARK: - Session Properties (delegate to AppSettings)

    /// The language the user chose in the app (`fr`, `en`, `es`, `de`).
    ///
    /// Sent as `Accept-Language` to services that write user-facing text —
    /// Chat Core writes its error messages in it. `en` before settings are
    /// injected, matching the app's default.
    public var languageCode: String {
        appSettings?.languageCode.rawValue ?? AppLanguage.en.rawValue
    }
    
    public var sessionId: String {
        get { appSettings?.chatSessionID ?? "" }
        set { appSettings?.chatSessionID = newValue }
    }
    
    public var userId: String {
        get { appSettings?.currentUserId ?? "" }
        set { appSettings?.currentUserId = newValue.isEmpty ? nil : newValue }
    }
    
    public var name: String {
        get { appSettings?.currentUserFullName ?? appSettings?.currentUserName ?? "" }
        set { 
            appSettings?.currentUserFullName = newValue.isEmpty ? nil : newValue
            appSettings?.currentUserName = newValue.isEmpty ? nil : newValue // Keep sync
        }
    }
    
    public var phone: String {
        get { appSettings?.currentUserPhone ?? "" }
        set { appSettings?.currentUserPhone = newValue.isEmpty ? nil : newValue }
    }
    
    public var tenantId: String {
        get { appSettings?.currentUserTenantId ?? "" }
        set { appSettings?.currentUserTenantId = newValue.isEmpty ? nil : newValue }
    }
    
    public var organisationId: String {
        get { appSettings?.currentUserOrganisationId ?? "" }
        set { appSettings?.currentUserOrganisationId = newValue.isEmpty ? nil : newValue }
    }
    
    public var avatar: String {
        get { appSettings?.currentUserAvatar ?? "" }
        set { appSettings?.currentUserAvatar = newValue.isEmpty ? nil : newValue }
    }

    /// The user's own "about" text. Persisted alongside the rest of the session
    /// so an edit survives relaunch instead of living only in a view model.
    public var bio: String {
        get { appSettings?.currentUserBio ?? "" }
        set { appSettings?.currentUserBio = newValue.isEmpty ? nil : newValue }
    }
    
    public var lastAuthenticatedAt: Date? {
        get { appSettings?.lastLoginDate }
        set { appSettings?.lastLoginDate = newValue }
    }
    
    public var expiresAt: Date? {
        get { appSettings?.chatSessionExpireDate }
        set { appSettings?.chatSessionExpireDate = newValue }
    }

    // MARK: - Extended Properties (not persisted in AppSettings - in-memory only)
    public var redirectUrl: String = ""
    public var appId: String = ""
    public var email: String = ""
    public var country: String = ""

    /// Runtime credentials for legacy upload paths — not persisted in session table.
    public var token: String = ""
    public var baseUrl: String = ""

    /// Asks the host for its access token each time one is needed, so a token the host renewed is
    /// used at once. Set by `ChatFeature`; `token` is only the fallback when it is not set.
    public var tokenProvider: (@Sendable () async -> String?)?

    /// The host's current access token for the legacy upload paths.
    public func currentToken() async -> String {
        if let provider = tokenProvider, let fresh = await provider(), !fresh.isEmpty { return fresh }
        return token
    }

    // MARK: - Legacy aliases (drop-in for CurrentUser.shared)

    public var currentUid: String {
        get { userId }
        set { userId = newValue }
    }

    public var userName: String {
        get { name }
        set { name = newValue }
    }

    public var userPhoneNumber: String {
        get { phone }
        set { phone = newValue }
    }

    public var userProfile: String {
        get { avatar }
        set { avatar = newValue }
    }

    // MARK: - Computed

    public var isAuthenticated: Bool {
        return appSettings?.isAuthenticated == true && !sessionId.isEmpty && !userId.isEmpty
    }

    public func update(from session: CurrentSession) {
        redirectUrl = session.redirectUrl
        sessionId = session.sessionId
        appId = session.appId
        userId = session.userId
        email = session.email
        name = session.name
        tenantId = session.tenantId
        organisationId = session.organisationId
        country = session.country
        phone = session.phone
        expiresAt = session.expiresAt
        lastAuthenticatedAt = session.lastAuthenticatedAt
    }

    public func update(from authInfo: AuthSessionInfo) {
        redirectUrl = authInfo.redirectUrl
        sessionId = authInfo.sessionId
        appId = authInfo.appId
        userId = authInfo.userId
        email = authInfo.email
        name = authInfo.name
        tenantId = authInfo.tenantId
        organisationId = authInfo.organisationId
        country = authInfo.country
        phone = authInfo.phone
        expiresAt = authInfo.expiresAt
        lastAuthenticatedAt = Date()
    }

    public func snapshot() -> CurrentSession {
        CurrentSession(
            redirectUrl: redirectUrl,
            sessionId: sessionId,
            appId: appId,
            userId: userId,
            email: email,
            name: name,
            tenantId: tenantId,
            organisationId: organisationId,
            country: country,
            phone: phone,
            expiresAt: expiresAt,
            lastAuthenticatedAt: lastAuthenticatedAt ?? Date()
        )
    }

    public func clear() {
        appSettings?.clearSession()
        
        // Clear extended properties
        redirectUrl = ""
        appId = ""
        email = ""
        country = ""
        avatar = ""
        token = ""
        baseUrl = ""
    }
}
