//
//  UserProfile.swift
//  FeatureChat
//
//  The signed-in user's own editable profile.
//

import Foundation

/// The signed-in user's own profile — the thing their contacts see.
///
/// Distinct from `UserContactProps`, which describes *other* people as they
/// arrive through contact sync.
public struct UserProfile: Equatable, Sendable {
    public let userId: String
    public var name: String
    public var bio: String
    public var avatarUrl: String

    public init(userId: String, name: String, bio: String, avatarUrl: String) {
        self.userId = userId
        self.name = name
        self.bio = bio
        self.avatarUrl = avatarUrl
    }
}

/// How a profile edit ended.
///
/// The edit is published first and only written to the device once identity
/// accepts it, so there is no in-between state to report: either contacts can
/// see the new profile and the device agrees, or nothing changed anywhere.
public enum UserProfileSaveOutcome: Equatable, Sendable {
    /// Accepted by the backend and stored locally.
    case published
    /// Rejected or unreachable — nothing was written, the old profile stands.
    case failed(reason: String)
}
