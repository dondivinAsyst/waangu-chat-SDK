//
//  AppSettingsProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

import Foundation

// MARK: - AppSettingsProtocol

public protocol AppSettingsProtocol: AnyObject {
    var chatSessionID: String { get set }
    var chatSessionExpireDate: Date? { get set }
    var hasChatSessionExpired: Bool { get }
    
    var hasCompletedOnboarding: Bool { get set }
    var lastSeenOnboardingPage: Int { get set }

    var colorScheme: String { get set }
    var languageCode: AppLanguage { get set }
    var pushEnabled: Bool { get set }
    var hapticsEnabled: Bool { get set }

    var isAuthenticated: Bool { get set }
    var currentUserId: String? { get set }
    var currentUserPhone: String? { get set }
    var currentUserName: String? { get set }
    var lastLoginDate: Date? { get set }

    // Chat-specific session properties
    var currentUserAvatar: String? { get set }
    /// The user's own "about" text, shown on their profile.
    var currentUserBio: String? { get set }
    var currentUserFullName: String? { get set }
    var currentUserTenantId: String? { get set }
    var currentUserOrganisationId: String? { get set }

    var debugOverlayEnabled: Bool { get set }
    var forceUpdateOverride: Bool { get set }
    var hasRequestedReview: Bool { get set }
    var sessionCountForReview: Int { get set }

    var lastLaunchedVersion: String? { get set }
    var launchCount: Int { get set }
    var selectedEnvironment: String? { get set }

    func clearSession()
    func incrementLaunchCount()
    
}
