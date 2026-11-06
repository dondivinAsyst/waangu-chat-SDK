//
//  UserProfileUseCasesProtocol.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

public protocol GetUserProfileUseCaseProtocol {
    func execute() async -> UserProfile
}

public protocol UpdateUserProfileUseCaseProtocol {
    /// Publishes the whole profile in one call.
    ///
    /// `avatarUrl` is the freshly uploaded photo, or `nil` to keep the one on
    /// file. Name and bio always come from the caller rather than from storage:
    /// splitting the photo into its own publish meant the first request carried
    /// the *saved* username while the user was looking at a different one.
    func execute(name: String, bio: String, avatarUrl: String?) async -> UserProfileSaveOutcome
}

public protocol UploadProfilePhotoUseCaseProtocol {
    /// Parks the photo in media storage and returns its URL. Publishing it onto
    /// the profile is `UpdateUserProfileUseCaseProtocol`'s job.
    func execute(imageData: Data) async -> Result<String, AppError>
}

public protocol UserProfileUseCasesProtocol {
    var getUserProfile: GetUserProfileUseCaseProtocol { get }
    var updateUserProfile: UpdateUserProfileUseCaseProtocol { get }
    var uploadProfilePhoto: UploadProfilePhotoUseCaseProtocol { get }
}
