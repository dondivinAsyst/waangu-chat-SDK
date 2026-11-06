//
//  AuthEvents.swift
//  AppModules
//
//  Created by Asyst on 6/17/26.
//

//
//  AuthEvents.swift
//  AppModules
//
//  Created by Asyst on 6/11/26.
//

//
//  AuthEvents.swift
//  AppModules
//
//  FeatureAuth/Sources/Events
//

import Foundation


// MARK: - Authentication Lifecycle

/// Publié après une authentification réussie (login, token refresh silencieux, restore session).
/// `ReplayableDomainEvent` : les abonnés tardifs (SyncCoordinator, MQTT, etc.)
/// reçoivent immédiatement le dernier état sans attendre un nouveau login.
public struct UserDidLoginEvent: ReplayableDomainEvent {

    public let userId: String
    public let timestamp: Date

    public init(userId: String, timestamp: Date = .now) {
        self.userId = userId
        self.timestamp = timestamp
    }

    public var description: String {
        "UserDidLoginEvent(userId: \(userId))"
    }
}

//will be removed in production

public struct UserChatDidLoginEvent: ReplayableDomainEvent {

    public let userId: String
    public let timestamp: Date

    public init(userId: String, timestamp: Date = .now) {
        self.userId = userId
        self.timestamp = timestamp
    }

    public var description: String {
        "UserChatDidLoginEvent(userId: \(userId))"
    }
}

/// Publié après un logout explicite ou une invalidation de session (401, token expiré non-renouvelable).
/// `ReplayableDomainEvent` : les modules qui se connectent après le logout
/// savent immédiatement qu'il n'y a pas de session active.
public struct UserDidLogoutEvent: ReplayableDomainEvent {

    public enum Reason: Sendable {
        case userInitiated
        case sessionExpired
        case accountSuspended
        case remoteRevocation
    }

    public let userId: String
    public let reason: Reason
    public let timestamp: Date

    public init(userId: String, reason: Reason, timestamp: Date = .now) {
        self.userId = userId
        self.reason = reason
        self.timestamp = timestamp
    }

    public var description: String {
        "UserDidLogoutEvent(userId: \(userId), reason: \(reason))"
    }
}

// MARK: - Session State Changes

/// Publié quand le token JWT est rafraîchi silencieusement.
/// Non-replayable : les modules n'ont pas besoin de l'historique des refreshes,
/// ils réagissent au moment où ça arrive (ex: ré-attacher le nouveau token aux requêtes en vol).
public struct TokenDidRefreshEvent: DomainEvent {

    public let userId: String
    public let timestamp: Date

    public init(userId: String, timestamp: Date = .now) {
        self.userId = userId
        self.timestamp = timestamp
    }

    public var description: String {
        "TokenDidRefreshEvent(userId: \(userId))"
    }
}

// MARK: - Auth Errors (matchable)

/// Publié quand une erreur d'auth nécessite une réaction des autres modules.
/// `MatchableDomainEvent` : permet à un module de filtrer uniquement
/// `EventBus.on(.tokenExpired)` sans recevoir les autres cas.
public enum AuthErrorEvent: MatchableDomainEvent {
    case tokenExpired
    case refreshFailed
    case biometricLockout

    public var description: String {
        switch self {
        case .tokenExpired:    "AuthErrorEvent.tokenExpired"
        case .refreshFailed:   "AuthErrorEvent.refreshFailed"
        case .biometricLockout: "AuthErrorEvent.biometricLockout"
        }
    }
}
