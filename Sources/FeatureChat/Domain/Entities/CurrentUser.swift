//
//  CurrentUser.swift
//  FeatureChat
//
//  Created by Refactoring on 5/5/26.
//  Updated by Architecture Team on 5/28/26 - Added persistence and 24-hour re-authentication
//  Updated by Consolidation on 6/16/26 - Converted to legacy compatibility adapter for AppSettings
//

import Foundation
import WaanguCoreKit

// MARK: - Current User Legacy Compatibility Adapter

/// Legacy compatibility adapter that delegates to AppSettings
/// This maintains backward compatibility while consolidating session management
/// DEPRECATED: Use AppSettings directly for new code
public final class CurrentUser {
    public static let shared = CurrentUser()
    
    private var appSettings: (any AppSettingsProtocol)?
    
    private init() {
        // No dependencies in init - will be injected later
    }
    
    // Injection method for AppSettings (called by ChatFeature during initialization)
    public func configure(appSettings: any AppSettingsProtocol) {
        self.appSettings = appSettings
    }
    
    // MARK: - Core Properties (delegate to AppSettings)
    
    public var id: String {
        get { appSettings?.currentUserId ?? "" }
        set { appSettings?.currentUserId = newValue.isEmpty ? nil : newValue }
    }
    
    public var tenantId: String {
        get { appSettings?.currentUserTenantId ?? "" }
        set { appSettings?.currentUserTenantId = newValue.isEmpty ? nil : newValue }
    }
    
    public var organisationId: String {
        get { appSettings?.currentUserOrganisationId ?? "" }
        set { appSettings?.currentUserOrganisationId = newValue.isEmpty ? nil : newValue }
    }
    
    public var phone: String {
        get { appSettings?.currentUserPhone ?? "" }
        set { appSettings?.currentUserPhone = newValue.isEmpty ? nil : newValue }
    }
    
    public var fullName: String {
        get { appSettings?.currentUserFullName ?? appSettings?.currentUserName ?? "" }
        set { 
            appSettings?.currentUserFullName = newValue.isEmpty ? nil : newValue
            appSettings?.currentUserName = newValue.isEmpty ? nil : newValue // Keep legacy sync
        }
    }
    
    public var avatar: String {
        get { appSettings?.currentUserAvatar ?? "" }
        set { appSettings?.currentUserAvatar = newValue.isEmpty ? nil : newValue }
    }
    
    public var lastAuthenticatedAt: Date? {
        get { appSettings?.lastLoginDate }
        set { appSettings?.lastLoginDate = newValue }
    }
    
    // MARK: - Extended Properties (not persisted in AppSettings - in-memory only)
    public var code: String = ""
    public var username: String = ""
    public var email: String = ""
    public var firstName: String = ""
    public var lastName: String = ""
    public var firebaseToken: [String] = []
    public var typeUser: String = ""
    public var status: String = ""
    public var province: String = ""
    public var country: String = ""
    public var township: String = ""
    public var isBanned: Bool = false
    public var warningCount: Int = 0
    public var reportCount: Int = 0
    public var trustScore: Int = 0
    public var isDeleted: Bool = false
    public var socialAccounts: [String] = []
    public var moduleContext: [String] = []
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var currentlyBanned: Bool = false
    public var active: Bool = false
    public var canLogin: Bool = false
    public var merchant: Bool = false
    public var agent: Bool = false
    public var doctor: Bool = false
    public var driver: Bool = false
    public var customer: Bool = false
    public var admin: Bool = false
    
    // MARK: - Runtime Properties (not persisted)
    public var token: String = ""
    public var baseUrl: String = ""
    
    // MARK: - Legacy Properties (for backward compatibility)
    public var currentUid: String {
        get { id }
        set { id = newValue }
    }
    
    public var userPhoneNumber: String {
        get { phone }
        set { phone = newValue }
    }
    
    public var userName: String {
        get { fullName }
        set { fullName = newValue }
    }
    
    public var userProfile: String {
        get { avatar }
        set { avatar = newValue }
    }
    
    // MARK: - Computed Properties
    
    /// Check if user is authenticated (delegates to AppSettings)
    public var isAuthenticated: Bool {
        return appSettings?.isAuthenticated == true && !id.isEmpty
    }
    
    /// Check if user needs re-authentication (24-hour check)
    public var needsReauthentication: Bool {
        guard let lastAuth = lastAuthenticatedAt else { return true }
        let hoursSinceAuth = Date().timeIntervalSince(lastAuth) / 3600
        return hoursSinceAuth >= 24
    }
    
    // MARK: - Public Methods
    
    /// Legacy update method (for backward compatibility)
    public func update(uid: String, token: String, phone: String, name: String, profile: String, baseUrl: String) {
        self.id = uid
        self.token = token
        self.phone = phone
        self.fullName = name
        self.avatar = profile
        self.baseUrl = baseUrl
        self.lastAuthenticatedAt = Date()
    }
    
    /// Clear all user data (logout) - delegates to AppSettings
    public func clear() {
        appSettings?.clearSession()
        
        // Clear extended properties
        code = ""
        username = ""
        email = ""
        firstName = ""
        lastName = ""
        firebaseToken = []
        typeUser = ""
        status = ""
        province = ""
        country = ""
        township = ""
        isBanned = false
        warningCount = 0
        reportCount = 0
        trustScore = 0
        isDeleted = false
        socialAccounts = []
        moduleContext = []
        createdAt = ""
        updatedAt = ""
        currentlyBanned = false
        active = false
        canLogin = false
        merchant = false
        agent = false
        doctor = false
        driver = false
        customer = false
        admin = false
        token = ""
        baseUrl = ""
    }
}
