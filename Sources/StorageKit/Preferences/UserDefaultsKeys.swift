//
//  UserDefaultsKeys.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

import Foundation

enum UserDefaultsKeys {
    
    enum ChatSession {
        static let hasChatSessionExpired = "chat.hasChatSessionExpired"
        static let chatSessionID = "chat.chatSessionID"
        static let chatExpireDate = "chat.chatExpireDate"
    }

    enum Onboarding {
        static let hasCompletedOnboarding = "onboarding.hasCompleted"
        static let lastSeenOnboardingPage = "onboarding.lastSeenPage"
    }

    enum Preferences {
        static let colorScheme    = "preferences.colorScheme"
        static let languageCode   = "preferences.languageCode"
        static let pushEnabled    = "preferences.pushEnabled"
        static let hapticsEnabled = "preferences.hapticsEnabled"
    }

    enum Session {
        static let isAuthenticated       = "session.isAuthenticated"
        static let currentUserId         = "session.currentUserId"
        static let currentUserPhone      = "session.currentUserPhone"
        static let currentUserName       = "session.currentUserName"
        static let lastLoginDate         = "session.lastLoginDate"
        
        // Chat-specific session properties
        static let currentUserAvatar     = "session.currentUserAvatar"
        static let currentUserBio        = "session.currentUserBio"
        static let currentUserFullName   = "session.currentUserFullName"
        static let currentUserTenantId   = "session.currentUserTenantId"
        static let currentUserOrganisationId = "session.currentUserOrganisationId"
    }

    enum FeatureFlags {
        static let debugOverlayEnabled   = "flags.debugOverlay"
        static let forceUpdateOverride   = "flags.forceUpdateOverride"
        static let hasRequestedReview    = "flags.hasRequestedReview"
        static let sessionCountForReview = "flags.sessionCountForReview"
    }

    enum App {
        static let lastLaunchedVersion = "app.lastLaunchedVersion"
        static let launchCount         = "app.launchCount"
        static let selectedEnvironment = "app.selectedEnvironment"
    }
}
