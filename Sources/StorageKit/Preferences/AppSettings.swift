//
//  AppSettings.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//
import WaanguCoreKit
import Foundation


// MARK: - AppSettings

public final class AppSettings: AppSettingsProtocol {
  
    
    

    public static let shared = AppSettings()

    private let store: any PreferenceStoreProtocol

    public init(store: any PreferenceStoreProtocol = PreferenceStore()) {
        self.store = store
    }
    
    // MARK: - CHAT
    
    public var chatSessionID: String {
        get { store.string(forKey: UserDefaultsKeys.ChatSession.chatSessionID) ?? "" }
        set { store.set(newValue, forKey: UserDefaultsKeys.ChatSession.chatSessionID) }
    }
    
    public var chatSessionExpireDate: Date? {
        get { store.object(forKey: UserDefaultsKeys.ChatSession.chatExpireDate) as? Date }
        set { store.set(newValue, forKey: UserDefaultsKeys.ChatSession.chatExpireDate) }
    }
    
    public var hasChatSessionExpired: Bool {
        guard let expireDate = chatSessionExpireDate else { return false }
        return Date() > expireDate
    }

    // MARK: - Onboarding

    public var hasCompletedOnboarding: Bool {
        get { store.bool(forKey: UserDefaultsKeys.Onboarding.hasCompletedOnboarding, default: false) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Onboarding.hasCompletedOnboarding) }
    }

    public var lastSeenOnboardingPage: Int {
        get { store.int(forKey: UserDefaultsKeys.Onboarding.lastSeenOnboardingPage, default: 0) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Onboarding.lastSeenOnboardingPage) }
    }

    // MARK: - Preferences

    public var colorScheme: String {
        get { store.string(forKey: UserDefaultsKeys.Preferences.colorScheme) ?? "system" }
        set { store.set(newValue, forKey: UserDefaultsKeys.Preferences.colorScheme) }
    }
    
    public var languageCode: AppLanguage {
           get {
               if let code = store.string(forKey: UserDefaultsKeys.Preferences.languageCode),
                  let lang = AppLanguage(rawValue: code) {
                   return lang
               }
               return .en // fallback par défaut
           }
           set {
               store.set(newValue.rawValue, forKey: UserDefaultsKeys.Preferences.languageCode)
           }
     }

    public var pushEnabled: Bool {
        get { store.bool(forKey: UserDefaultsKeys.Preferences.pushEnabled, default: true) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Preferences.pushEnabled) }
    }

    public var hapticsEnabled: Bool {
        get { store.bool(forKey: UserDefaultsKeys.Preferences.hapticsEnabled, default: true) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Preferences.hapticsEnabled) }
    }

    // MARK: - Session

    public var isAuthenticated: Bool {
        get { store.bool(forKey: UserDefaultsKeys.Session.isAuthenticated, default: false) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.isAuthenticated) }
    }

    public var currentUserId: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserId) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserId) }
    }

    public var currentUserPhone: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserPhone) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserPhone) }
    }

    public var currentUserName: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserName) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserName) }
    }

    public var lastLoginDate: Date? {
        get { store.object(forKey: UserDefaultsKeys.Session.lastLoginDate) as? Date }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.lastLoginDate) }
    }

    // MARK: - Chat-specific session properties

    public var currentUserAvatar: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserAvatar) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserAvatar) }
    }

    public var currentUserBio: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserBio) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserBio) }
    }

    public var currentUserFullName: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserFullName) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserFullName) }
    }

    public var currentUserTenantId: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserTenantId) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserTenantId) }
    }

    public var currentUserOrganisationId: String? {
        get { store.string(forKey: UserDefaultsKeys.Session.currentUserOrganisationId) }
        set { store.set(newValue, forKey: UserDefaultsKeys.Session.currentUserOrganisationId) }
    }

    // MARK: - Feature Flags

    public var debugOverlayEnabled: Bool {
        get { store.bool(forKey: UserDefaultsKeys.FeatureFlags.debugOverlayEnabled, default: false) }
        set { store.set(newValue, forKey: UserDefaultsKeys.FeatureFlags.debugOverlayEnabled) }
    }

    public var forceUpdateOverride: Bool {
        get { store.bool(forKey: UserDefaultsKeys.FeatureFlags.forceUpdateOverride, default: false) }
        set { store.set(newValue, forKey: UserDefaultsKeys.FeatureFlags.forceUpdateOverride) }
    }

    public var hasRequestedReview: Bool {
        get { store.bool(forKey: UserDefaultsKeys.FeatureFlags.hasRequestedReview, default: false) }
        set { store.set(newValue, forKey: UserDefaultsKeys.FeatureFlags.hasRequestedReview) }
    }

    public var sessionCountForReview: Int {
        get { store.int(forKey: UserDefaultsKeys.FeatureFlags.sessionCountForReview, default: 0) }
        set { store.set(newValue, forKey: UserDefaultsKeys.FeatureFlags.sessionCountForReview) }
    }

    // MARK: - App State

    public var lastLaunchedVersion: String? {
        get { store.string(forKey: UserDefaultsKeys.App.lastLaunchedVersion) }
        set { store.set(newValue, forKey: UserDefaultsKeys.App.lastLaunchedVersion) }
    }

    public var launchCount: Int {
        get { store.int(forKey: UserDefaultsKeys.App.launchCount, default: 0) }
        set { store.set(newValue, forKey: UserDefaultsKeys.App.launchCount) }
    }

    public var selectedEnvironment: String? {
        get { store.string(forKey: UserDefaultsKeys.App.selectedEnvironment) }
        set { store.set(newValue, forKey: UserDefaultsKeys.App.selectedEnvironment) }
    }

    // MARK: - Helpers

    public func clearSession() {
        store.removeAll(forKeys: [
            // Session keys
            UserDefaultsKeys.Session.isAuthenticated,
            UserDefaultsKeys.Session.currentUserId,
            UserDefaultsKeys.Session.currentUserPhone,
            UserDefaultsKeys.Session.currentUserName,
            UserDefaultsKeys.Session.lastLoginDate,
            UserDefaultsKeys.Session.currentUserAvatar,
            UserDefaultsKeys.Session.currentUserBio,
            UserDefaultsKeys.Session.currentUserFullName,
            UserDefaultsKeys.Session.currentUserTenantId,
            UserDefaultsKeys.Session.currentUserOrganisationId,
            
            // Chat session keys
            UserDefaultsKeys.ChatSession.chatSessionID,
            UserDefaultsKeys.ChatSession.chatExpireDate,
            UserDefaultsKeys.ChatSession.hasChatSessionExpired
        ])
    }

    public func incrementLaunchCount() {
        launchCount += 1
    }
}
