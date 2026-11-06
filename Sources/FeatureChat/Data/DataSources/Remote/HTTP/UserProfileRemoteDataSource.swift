//
//  UserProfileRemoteDataSource.swift
//  FeatureChat
//

import Foundation

/// Publishes the signed-in user's profile to the identity service.
///
/// This is what makes a profile edit visible to contacts: the same record that
/// `POST /identity/contacts/sync` reads back when other people sync their
/// address book. Implemented by `HTTPUserProfileDataSource`.
protocol UserProfileRemoteDataSourceProtocol {
    func updateProfile(_ profile: UserProfile) async throws
}

enum UserProfileRemoteError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No profile endpoint is configured for this build."
        }
    }
}

/// Refuses loudly rather than reporting a success that never left the device.
/// Kept for tests and for any build that deliberately runs without identity.
struct UnavailableUserProfileRemoteDataSource: UserProfileRemoteDataSourceProtocol {
    func updateProfile(_ profile: UserProfile) async throws {
        throw UserProfileRemoteError.notConfigured
    }
}
