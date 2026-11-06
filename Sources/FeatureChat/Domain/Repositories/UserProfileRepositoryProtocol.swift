//
//  UserProfileRepositoryProtocol.swift
//  FeatureChat
//

import Foundation

public protocol UserProfileRepositoryProtocol {
    /// The profile as this device currently knows it.
    func loadProfile() async -> UserProfile

    /// Stores the profile locally, then publishes it so contacts can see it.
    ///
    /// Returns whether the publish succeeded — a local-only save is a real
    /// outcome, not a failure, and the caller is expected to say so.
    func saveProfile(_ profile: UserProfile) async -> UserProfileSaveOutcome
}
