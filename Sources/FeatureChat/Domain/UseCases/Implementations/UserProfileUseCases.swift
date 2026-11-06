//
//  UserProfileUseCases.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

// MARK: - Get

final class GetUserProfileUseCase: GetUserProfileUseCaseProtocol {
    private let repository: UserProfileRepositoryProtocol

    init(repository: UserProfileRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async -> UserProfile {
        await repository.loadProfile()
    }
}

// MARK: - Publish the profile

final class UpdateUserProfileUseCase: UpdateUserProfileUseCaseProtocol {
    private let repository: UserProfileRepositoryProtocol

    init(repository: UserProfileRepositoryProtocol) {
        self.repository = repository
    }

    func execute(name: String, bio: String, avatarUrl: String?) async -> UserProfileSaveOutcome {
        var profile = await repository.loadProfile()
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if let avatarUrl {
            profile.avatarUrl = avatarUrl
        }
        return await repository.saveProfile(profile)
    }
}

// MARK: - Upload photo

final class UploadProfilePhotoUseCase: UploadProfilePhotoUseCaseProtocol {
    private let repository: UserProfileRepositoryProtocol
    private let uploadProfileImage: UploadProfileImageUseCaseProtocol

    init(
        repository: UserProfileRepositoryProtocol,
        uploadProfileImage: UploadProfileImageUseCaseProtocol
    ) {
        self.repository = repository
        self.uploadProfileImage = uploadProfileImage
    }

    func execute(imageData: Data) async -> Result<String, AppError> {
        let profile = await repository.loadProfile()
        let fileName = "profile_\(profile.userId)_\(Int(Date().timeIntervalSince1970)).jpg"

        // Only parks the file in media storage — the URL still has to be
        // published with the rest of the profile before anyone else sees it.
        return await uploadProfileImage.execute(
            userId: profile.userId,
            imageData: imageData,
            fileName: fileName
        )
    }
}

// MARK: - Container

final class UserProfileUseCases: UserProfileUseCasesProtocol {
    let getUserProfile: GetUserProfileUseCaseProtocol
    let updateUserProfile: UpdateUserProfileUseCaseProtocol
    let uploadProfilePhoto: UploadProfilePhotoUseCaseProtocol

    init(
        repository: UserProfileRepositoryProtocol,
        uploadProfileImage: UploadProfileImageUseCaseProtocol
    ) {
        self.getUserProfile = GetUserProfileUseCase(repository: repository)
        self.updateUserProfile = UpdateUserProfileUseCase(repository: repository)
        self.uploadProfilePhoto = UploadProfilePhotoUseCase(
            repository: repository,
            uploadProfileImage: uploadProfileImage
        )
    }
}
