//
//  ProfileEditViewModel.swift
//  FeatureChat
//

import Foundation
import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
@MainActor
final class ProfileEditViewModel: ObservableObject {

    @Published var name: String = ""
    @Published var bio: String = ""
    @Published var avatarUrl: String = ""

    /// Photo the user picked and cropped but hasn't saved yet. Picking and
    /// cropping are `AvatarPickerButton`'s job; this only ever sees the result.
    @Published var pendingPhoto: UIImage?

    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// Matches the backend column, and keeps a bio from growing unbounded in a
    /// field that renders on one line everywhere else in the app.
    static let bioCharacterLimit = 139

    private let useCases: UserProfileUseCasesProtocol
    private let translationService: (any TranslationServiceProtocol)?
    private var loaded: UserProfile?

    var hasChanges: Bool {
        guard let loaded else { return false }
        if pendingPhoto != nil { return true }
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != loaded.name
            || bio.trimmingCharacters(in: .whitespacesAndNewlines) != loaded.bio
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasChanges
            && !isSaving
    }

    init(
        useCases: UserProfileUseCasesProtocol,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.useCases = useCases
        self.translationService = translationService
        Task { await load() }
    }

    func load() async {
        let profile = await useCases.getUserProfile.execute()
        loaded = profile
        name = profile.name
        bio = profile.bio
        avatarUrl = profile.avatarUrl
    }

    func onPhotoPicked(_ image: UIImage) {
        pendingPhoto = image
    }

    func onPhotoLoadFailed() {
        errorMessage = t(ChatTranslationKeys.PROFILE_PHOTO_LOAD_FAILED)
    }

    func onBioChanged(_ newValue: String) {
        if newValue.count > Self.bioCharacterLimit {
            bio = String(newValue.prefix(Self.bioCharacterLimit))
        }
    }

    /// Uploads the photo if there is one, then publishes the profile once.
    ///
    /// Deliberately a single publish: when the photo had its own, that first
    /// request was built from stored values and sent the *old* username while
    /// the user was looking at a new one — and a failure on the second left the
    /// photo published with the name change dropped.
    func save() async {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var uploadedAvatarUrl: String?
        if let pendingPhoto {
            let data = ChatImageSendEncoder.encodeAvatar(pendingPhoto)
            switch await useCases.uploadProfilePhoto.execute(imageData: data) {
            case .failure(let error):
                errorMessage = error.localizedDescription
                return
            case .success(let url):
                uploadedAvatarUrl = url
            }
        }

        let outcome = await useCases.updateUserProfile.execute(
            name: name,
            bio: bio,
            avatarUrl: uploadedAvatarUrl
        )

        switch outcome {
        case .published:
            pendingPhoto = nil
        case .failed(let reason):
            errorMessage = reason
        }

        await load()
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }
}
