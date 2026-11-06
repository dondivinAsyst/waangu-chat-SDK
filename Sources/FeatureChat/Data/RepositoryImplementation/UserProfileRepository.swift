//
//  UserProfileRepository.swift
//  FeatureChat
//

import Foundation

/// Store for the signed-in user's own profile.
///
/// The change is published to identity first and only written to the device
/// once that succeeds. Doing it the other way round lets the phone show a name
/// or photo that no contact will ever receive through contact sync, so a failed
/// publish leaves the stored profile untouched and says so.
final class UserProfileRepository: UserProfileRepositoryProtocol {
    private let session: CurrentSessionInfo
    private let remoteDataSource: UserProfileRemoteDataSourceProtocol

    /// `remoteDataSource` has no default on purpose — every save now depends on
    /// it, and a defaulted stand-in would fail silently for whoever forgot it.
    init(
        session: CurrentSessionInfo = .shared,
        remoteDataSource: UserProfileRemoteDataSourceProtocol
    ) {
        self.session = session
        self.remoteDataSource = remoteDataSource
    }

    func loadProfile() async -> UserProfile {
        UserProfile(
            userId: session.currentUid,
            name: session.userName,
            bio: session.bio,
            avatarUrl: session.userProfile
        )
    }

    func saveProfile(_ profile: UserProfile) async -> UserProfileSaveOutcome {
        do {
            try await remoteDataSource.updateProfile(profile)
        } catch {
            return .failed(reason: error.localizedDescription)
        }

        // Only now — identity has the change, so the device can match it.
        session.userName = profile.name
        session.bio = profile.bio
        session.userProfile = profile.avatarUrl

        return .published
    }
}
