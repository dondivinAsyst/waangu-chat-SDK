//
//  ProfileEditView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// The signed-in user's own profile: photo, name and bio, all editable.
///
/// Replaces the two-field alert that used to hang off the settings header and
/// threw the bio away on save.
@available(iOS 16.0, *)
struct ProfileEditView: View {
    @StateObject private var viewModel: ProfileEditViewModel
    private let translationService: (any TranslationServiceProtocol)?

    init(
        useCases: UserProfileUseCasesProtocol,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ProfileEditViewModel(
                useCases: useCases,
                translationService: translationService
            )
        )
        self.translationService = translationService
    }

    var body: some View {
        List {
            photoSection
            nameSection
            bioSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t(ChatTranslationKeys.PROFILE_TITLE))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button(common("save")) {
                        Task { await viewModel.save() }
                    }
                    .bold()
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .disabled(viewModel.isSaving)
        .customAlert(
            title: t(ChatTranslationKeys.PROFILE_SAVE_FAILED),
            message: viewModel.errorMessage,
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { viewModel.errorMessage = nil }
        )
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                avatar

                AvatarPickerButton(
                    onPicked: { viewModel.onPhotoPicked($0) },
                    onLoadFailed: { viewModel.onPhotoLoadFailed() }
                ) {
                    Text(t(ChatTranslationKeys.PROFILE_CHANGE_PHOTO))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var avatar: some View {
        if let photo = viewModel.pendingPhoto {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(Circle())
        } else if !viewModel.avatarUrl.isEmpty {
            CircularProfileImageView(viewModel.avatarUrl, size: .custom(100))
        } else {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                }
        }
    }

    private var nameSection: some View {
        Section {
            TextField(t(ChatTranslationKeys.SETTINGS_USERNAME), text: $viewModel.name)
                .textInputAutocapitalization(.words)
        } header: {
            Text(t(ChatTranslationKeys.SETTINGS_USERNAME))
        } footer: {
            Text(t(ChatTranslationKeys.PROFILE_NAME_FOOTER))
        }
    }

    private var bioSection: some View {
        Section {
            TextField(
                t(ChatTranslationKeys.SETTINGS_BIO),
                text: $viewModel.bio,
                axis: .vertical
            )
            .lineLimit(1...4)
            .onChange(of: viewModel.bio) { newValue in
                viewModel.onBioChanged(newValue)
            }
        } header: {
            Text(t(ChatTranslationKeys.SETTINGS_BIO))
        } footer: {
            Text("\(viewModel.bio.count)/\(ProfileEditViewModel.bioCharacterLimit)")
                .monospacedDigit()
        }
    }

    // MARK: - Translation

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
